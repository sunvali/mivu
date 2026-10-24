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
                .tint(.diaryAccent)
                .containerBackground(Color.diarySurface, for: .widget)
                .widgetURL(URL(string: "mivu://today"))
        }
        .configurationDisplayName("Calories")
        .description("Today's calories, with Snap It and Coach one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        // Pip stands in the corner, so the system families pad their own content instead.
        .contentMarginsDisabled()
    }
}

/// Mirrors the Today card: a bold intake figure, the goal bar, capsule actions and Pip beside them.
struct CaloriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot?
    /// The goal bar and the action row share one width so a full bar reads as full.
    private let actionRowWidth: CGFloat = 220

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        // Capped like system widgets: past this size the figure, actions and Pip cannot share a fixed widget.
        case .systemMedium: medium.dynamicTypeSize(...DynamicTypeSize.xLarge)
        default: small.dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }

    // MARK: Home Screen

    private var small: some View {
        ZStack(alignment: .bottomTrailing) {
            pip(height: 76)
            VStack(alignment: .leading, spacing: 0) {
                if let snapshot, snapshot.hasDiary {
                    figure(snapshot, size: 32, eyebrow: false)
                    Spacer(minLength: 8)
                    goalBar(snapshot).frame(width: 64, alignment: .leading)
                } else {
                    setUpText
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }

    private var medium: some View {
        ZStack(alignment: .bottomTrailing) {
            pip(height: 120)
            VStack(alignment: .leading, spacing: 0) {
                if let snapshot, snapshot.hasDiary {
                    figure(snapshot, size: 38, eyebrow: true)
                    goalBar(snapshot).frame(maxWidth: actionRowWidth, alignment: .leading).padding(.top, 10)
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Button(intent: LogFoodIntent()) {
                            capsule("Snap It", systemImage: "camera.fill", fill: .diaryAccent, text: .diaryActionText)
                        }
                        Button(intent: OpenCoachIntent()) {
                            capsule("Coach", systemImage: "bubble.left.fill", fill: .diarySummarySurface, text: .diaryAccent)
                        }
                    }
                    .buttonStyle(.plain)
                    // Stops short of Pip; larger text shrinks the labels instead of sliding under him.
                    .frame(maxWidth: actionRowWidth, alignment: .leading)
                } else {
                    setUpText
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }

    private func figure(_ snapshot: WidgetSnapshot, size: CGFloat, eyebrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if eyebrow { Text("Today").font(.caption.weight(.semibold)).foregroundStyle(Color.diarySecondary) }
            Text(kcal(snapshot.eaten))
                .font(.system(size: size, weight: .bold)).tracking(-1).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(Color.diaryText)
            Text(snapshot.target.map { "of \(kcal($0)) kcal" } ?? "kcal recorded")
                .font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(Color.diaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    @ViewBuilder private func goalBar(_ snapshot: WidgetSnapshot) -> some View {
        if snapshot.target != nil {
            Capsule().fill(Color.diaryAccent.opacity(0.16))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(Color.diaryAccent).widgetAccentable()
                            .frame(width: max(proxy.size.width * snapshot.ringFraction, snapshot.eaten > 0 ? 6 : 0))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
        } else {
            Text("Set a target").font(.caption.weight(.semibold)).foregroundStyle(Color.diaryAccent).fixedSize()
        }
    }

    private var setUpText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Set up Mivu").font(.headline).foregroundStyle(Color.diaryText)
            Text("Pip will track your day here.").font(.caption).foregroundStyle(Color.diarySecondary)
        }
    }

    private func capsule(_ title: String, systemImage: String, fill: Color, text: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).imageScale(.small)
            Text(title)
        }
        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(text)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(fill, in: .capsule)
    }

    private func pip(height: CGFloat) -> some View {
        // Cut from the approved painting (design-system/mivu/characters/pip/widget), not the animation rig.
        Image("PipWave").resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFit()
            .frame(height: height)
            .padding([.trailing, .bottom], 10)
            .accessibilityHidden(true)
    }

    // MARK: Lock Screen

    @ViewBuilder private var circular: some View {
        if let snapshot, snapshot.hasDiary {
            Gauge(value: snapshot.ringFraction) {
                Text("kcal")
            } currentValueLabel: {
                Text(kcal(snapshot.eaten)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(spoken(snapshot))
        } else {
            Image(systemName: "fork.knife").font(.title2).widgetAccentable().accessibilityLabel("Set up Mivu")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let snapshot, snapshot.hasDiary {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mivu").font(.headline).widgetAccentable()
                Text(snapshot.target.map { "\(kcal(snapshot.eaten)) / \(kcal($0)) kcal" } ?? "\(kcal(snapshot.eaten)) kcal recorded")
                    .minimumScaleFactor(0.7).lineLimit(1)
                if snapshot.target != nil {
                    Gauge(value: snapshot.ringFraction) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(snapshot))
        } else {
            Label("Set up Mivu", systemImage: "fork.knife").widgetAccentable()
        }
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
