import Foundation

/// One workout as Apple Health reports it; `id` is the `HKWorkout` UUID and becomes the diary workout's ID.
struct HealthWorkout: Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let activeKcal: Double?
    let sourceName: String
    let kind: WorkoutKind
}

extension DiaryTransaction {
    /// Applies Health changes to today and the 6 days before; older days stay as they were.
    /// Never creates a day, and never brings back a workout deleted in Mivu (its ID is tombstoned).
    func applyHealthWorkouts(_ upserts: [HealthWorkout], deletedIDs: [UUID], now: Date) throws {
        let zone = head.profile.timeZoneID
        let window = Set(ProgressAnalytics.window(endingOn: diaryDateLabel(now, zone: zone), days: 7, offset: 0, zone: zone))
        func inWindow(_ workout: WorkoutSession) throws -> Bool { window.contains(try database.trackingDay(id: workout.dayID).localDate) }
        for id in Set(deletedIDs) {
            guard let existing = try existingWorkout(id), existing.isFromHealth, try inWindow(existing) else { continue }
            try deleteWorkout(id: id, revision: existing.revision)
        }
        for health in upserts {
            let label = diaryDateLabel(health.start, zone: zone)
            guard window.contains(label), health.end.timeIntervalSince1970.isFinite,
                  try database.mutationInteger("SELECT COUNT(*) FROM workout_tombstone WHERE id = ?", [.text(health.id.uuidString)]) == 0,
                  let day = try existingDay(localDate: label, preferredZone: zone) else { continue }
            let existing = try existingWorkout(health.id)
            if let existing { guard existing.isFromHealth, try inWindow(existing) else { continue } }
            let name = String(health.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
            var value = WorkoutSession(id: health.id, dayID: day.id, performedAt: health.start, timePrecision: .exact,
                revision: existing?.revision ?? 1, kind: health.kind,
                durationMinutes: min(max(Int((health.end.timeIntervalSince(health.start) / 60).rounded()), 1), 1440), exercises: [],
                estimatedBurnKcal: health.activeKcal.flatMap { $0.isFinite ? min(max($0, 0), 100_000) : nil },
                burnSource: .health, healthSource: name.isEmpty ? "Apple Health" : name)
            if let existing {
                guard existing != value else { continue }
                value.revision = existing.revision + 1
            }
            try saveWorkout(value)
        }
    }

    private func existingWorkout(_ id: UUID) throws -> WorkoutSession? {
        do { return try workout(id: id) } catch DiaryError.notFound { return nil }
    }

    /// Prefers the day recorded in the profile's time zone when travel left two days with the same date.
    private func existingDay(localDate: String, preferredZone: String) throws -> TrackingDay? {
        let days = try records("day", clause: "json_extract(CAST(payload AS TEXT), '$.localDate') = ?", values: [.text(localDate)]).map { row in
            let day = try database.decode(TrackingDay.self, row); try validateTrackingDayFields(day); return day
        }
        return days.first { $0.timeZoneID == preferredZone } ?? days.first
    }
}
