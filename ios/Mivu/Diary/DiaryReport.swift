import UIKit

/// A shareable view of saved diary data over a range of local dates, kept apart from the UI so a later sender can reuse it.
struct DiaryReport {
    enum Format: String, CaseIterable, Identifiable { case pdf = "PDF", csv = "CSV"; var id: Self { self } }
    struct Meal { var time: String; var name: String; var totals: NutritionTotals }
    struct Day { var localDate: String; var totals: NutritionTotals; var target: NutritionValues?; var weight: WeightEntry?; var meals: [Meal] }
    struct Weight { var localDate: String; var time: String; var entry: WeightEntry }

    let profileName: String
    let days: [Day]
    let weights: [Weight]
    private let label: String

    init(_ snapshot: DiarySnapshot, from: String?, through: String?) {
        func inRange(_ date: String) -> Bool { (from.map { date >= $0 } ?? true) && (through.map { date <= $0 } ?? true) }
        func clock(_ date: Date, _ zoneID: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: zoneID) ?? .current
            return formatter.string(from: date)
        }
        let dayByID = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.id, $0) })
        weights = snapshot.weights.compactMap { entry in
            let zone = entry.dayID.flatMap { dayByID[$0]?.timeZoneID } ?? snapshot.profile.timeZoneID
            let localDate = entry.dayID.flatMap { dayByID[$0]?.localDate } ?? ISO8601DateFormatter.string(from: entry.measuredAt, timeZone: TimeZone(identifier: zone) ?? .current, formatOptions: .withFullDate)
            guard inRange(localDate) else { return nil }
            return Weight(localDate: localDate, time: entry.timePrecision == .dateOnly ? "" : clock(entry.measuredAt, zone), entry: entry)
        }.sorted { $0.entry.measuredAt < $1.entry.measuredAt }
        days = snapshot.days.filter { inRange($0.localDate) }.sorted { $0.localDate < $1.localDate }.map { [weights] day in
            let meals = snapshot.meals.filter { $0.dayID == day.id && $0.isSaved }.sorted { $0.eatenAt < $1.eatenAt }.map { meal in
                let name = meal.items.map(\.name).joined(separator: ", ")
                let text = meal.submissions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Meal(time: meal.timePrecision == .dateOnly ? "" : clock(meal.eatenAt, day.timeZoneID),
                            name: name.isEmpty ? (text.isEmpty ? "Meal" : text) : name, totals: meal.totals)
            }
            return Day(localDate: day.localDate, totals: snapshot.totals(dayID: day.id), target: snapshot.goal(on: day.localDate)?.targets,
                       weight: weights.last { $0.localDate == day.localDate }?.entry, meals: meals)
        }
        profileName = snapshot.profile.name
        label = days.isEmpty ? "empty" : "\(days.first!.localDate) to \(days.last!.localDate)"
    }

    // MARK: CSV

    var mealsCSV: String {
        csv(["Date", "Time", "Meal", "Calories (kcal)", "Protein (g)", "Carbs (g)", "Fat (g)"], days.flatMap { day in
            day.meals.map { [day.localDate, $0.time, $0.name, number($0.totals.kcal), number($0.totals.protein), number($0.totals.carbs), number($0.totals.fat)] }
        })
    }
    var daysCSV: String {
        csv(["Date", "Calories (kcal)", "Calorie target (kcal)", "Protein (g)", "Protein target (g)", "Carbs (g)", "Fat (g)", "Weight"], days.map {
            [$0.localDate, number($0.totals.kcal), number($0.target?.kcal), number($0.totals.protein), number($0.target?.protein),
             number($0.totals.carbs), number($0.totals.fat), $0.weight.map { "\(number($0.value)) \($0.unit)" } ?? ""]
        })
    }
    var weightsCSV: String {
        csv(["Date", "Time", "Weight", "Unit"], weights.map { [$0.localDate, $0.time, number($0.entry.value), $0.entry.unit] })
    }

    private func csv(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(Self.field).joined(separator: ",") + "\r\n" }.joined()
    }
    /// RFC 4180 quoting, and a leading apostrophe so spreadsheets never run user text as a formula.
    private static func field(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil { value = "'" + value }
        return value.contains(where: { ",\"\r\n".contains($0) }) ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
    }
    func number(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) } ?? ""
    }

    // MARK: Files

    func write(_ format: Format, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files: [(String, Data)] = switch format {
        case .pdf: [("Mivu report \(label).pdf", pdfData())]
        case .csv: [("Mivu meals \(label).csv", Data(mealsCSV.utf8)), ("Mivu days \(label).csv", Data(daysCSV.utf8)), ("Mivu weights \(label).csv", Data(weightsCSV.utf8))]
        }
        return try files.map { name, data in
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }
    }
}
