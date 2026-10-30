import Foundation
import Observation
import UIKit

struct MealDraft: Equatable {
    var submissionID = UUID()
    var text = ""
    var photos: [Data] = []
    var reviewFirst = false
    var isValid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty }
}

enum DiaryCaptureDestination: Equatable, Sendable {
    case automatic, day(UUID, dateOnly: Bool), newDay, meal(UUID)
}
enum DiaryCaptureResult: Equatable, Sendable {
    case saved(UUID), failed
}

@MainActor @Observable final class DiaryViewModel {
    let store: DiaryStore
    let sampleMode: Bool
    let photoWorkLimiter: PhotoWorkLimiter
    let exportCoordinator: DiaryExportCoordinator
    private let profileSelection: @Sendable (UUID) async throws -> DiaryReadModel
    // Foreground actions have their own load boundary; subscriber loads are independent.
    private let actionReadModelLoading: @Sendable (UUID) async throws -> DiaryReadModel
    private let subscriberReadModelLoading: @Sendable (UUID) async throws -> DiaryReadModel
    private let mealDetailLoading: @Sendable (UUID, UUID) async throws -> MealReadModel
    private let dayDetailLoading: @Sendable (UUID, UUID) async throws -> DiaryDayReadModel
    private let manualNutritionSaving: @Sendable (ManualNutritionPayload, DiarySelectionOwnership) async throws -> ManualNutritionSaveResult
    @ObservationIgnored private var captureTask: Task<DiaryCaptureResult, Never>?
    @ObservationIgnored private let beginCaptureProtection: @MainActor () -> (@MainActor () -> Void)
    private let captureDayAssignment: @Sendable (Date, DiarySelectionOwnership) async throws -> DayAssignment
    private let deviceTimeZone: @Sendable () -> TimeZone
    private let preferences: UserDefaults?
    let backup: FolderBackup?
    private(set) var readModel: DiaryReadModel?
    private(set) var selection: DiarySelectionOwnership?
    private(set) var workStatus = CoachWorkStatus()
    private(set) var photoLoader: DiaryPhotoLoader?
    private(set) var photoRequestGeneration: UInt64 = 0
    private(set) var changeGeneration: UInt64 = 0
    private(set) var savedMealID: UUID?
    private struct CaptureAttempt {
        let selection: DiarySelectionOwnership
        let draft: MealDraft
        let destination: DiaryCaptureDestination
        let photoRole: PhotoRole
        let at: Date
        let photos: [MealPhoto]
        let isNew: Bool
        var resolvedDestination: DiaryCaptureDestination?
    }
    private var manualCaptureAttempt: CaptureAttempt?
    private var exactMeals: [UUID: MealReadModel] = [:]
    private var exactDays: [UUID: DiaryDayReadModel] = [:]
    private var mealDetailRequests: [UUID: UUID] = [:]
    private var dayDetailRequests: [UUID: UUID] = [:]
    var resumeCoach: (() -> Void)?
    var retryCoachMeal: ((UUID) -> Void)?
    var profiles: [DiaryProfile] = []
    var errorMessage: String?
    var manualDayChanged = false
    var isSaving = false
    private(set) var isChangingProfile = false
    private(set) var captureReceipt: UUID?
    private(set) var companionCaptureEvent: CompanionEvent?
    private(set) var companionReviewEvent: CompanionEvent?
    private(set) var companionHabitEvent: CompanionEvent?
    private var companionReviewSubmissions: [UUID: Set<UUID>] = [:]
    var restoreGeneration = 0
    var backupStatus = FolderBackupStatus()
    private var backupGeneration: UUID?
    private var backupTask: Task<Void, Never>?
    private var backupTaskID: UUID?
    private var backupRequested: (DiarySelectionOwnership, Int, UUID)?
    private var backupScheduledRevision: Int?
    private var changesTask: Task<Void, Never>?
    private var sampleProcessingAllowed = true
    private var workerRerun = false
    private var worker: Task<Void, Never>?
    private var workerID: UUID?
    @ObservationIgnored private var memoryTask: Task<Void, Never>?

    init(store: DiaryStore, sampleMode: Bool = false, preferences: UserDefaults? = nil, backup: FolderBackup? = nil,
         profileSelection: (@Sendable (UUID) async throws -> DiaryReadModel)? = nil,
         actionReadModelLoading: (@Sendable (UUID) async throws -> DiaryReadModel)? = nil,
         subscriberReadModelLoading: (@Sendable (UUID) async throws -> DiaryReadModel)? = nil,
         mealDetailLoading: (@Sendable (UUID, UUID) async throws -> MealReadModel)? = nil,
         dayDetailLoading: (@Sendable (UUID, UUID) async throws -> DiaryDayReadModel)? = nil,
         photoWorkLimiter: PhotoWorkLimiter = PhotoWorkLimiter(), exportCoordinator: DiaryExportCoordinator? = nil,
         manualNutritionSaving: (@Sendable (ManualNutritionPayload, DiarySelectionOwnership) async throws -> ManualNutritionSaveResult)? = nil,
         deviceTimeZone: @Sendable @escaping () -> TimeZone = { .current },
         beginCaptureProtection: @escaping @MainActor () -> (@MainActor () -> Void) = { CoachCaptureProtection.begin() },
         captureDayAssignment: (@Sendable (Date, DiarySelectionOwnership) async throws -> DayAssignment)? = nil) {
        self.manualNutritionSaving = manualNutritionSaving ?? { try await store.saveManualNutrition($0, expectedSelection: $1, expectedProfileID: $0.profileID) }
        self.captureDayAssignment = captureDayAssignment ?? { try await store.dayAssignment(at: $0, expectedSelection: $1, expectedProfileID: $1.identity.profileID) }
        self.beginCaptureProtection = beginCaptureProtection
        self.deviceTimeZone = deviceTimeZone
        self.store = store; self.sampleMode = sampleMode; self.preferences = preferences; self.backup = backup
        self.profileSelection = profileSelection ?? { try await store.selectProfile($0) }
        self.actionReadModelLoading = actionReadModelLoading ?? { try await store.diaryReadModel(expectedProfileID: $0) }
        self.subscriberReadModelLoading = subscriberReadModelLoading ?? { try await store.diaryReadModel(expectedProfileID: $0) }
        self.mealDetailLoading = mealDetailLoading ?? { try await store.meal(id: $0, expectedProfileID: $1) }
        self.dayDetailLoading = dayDetailLoading ?? { try await store.diaryDay(id: $0, expectedProfileID: $1) }
        self.photoWorkLimiter = photoWorkLimiter; self.exportCoordinator = exportCoordinator ?? DiaryExportCoordinator(store: store)
        memoryTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                guard let self, !Task.isCancelled else { return }
                await self.photoLoader?.purgeForMemoryPressure(); self.photoRequestGeneration &+= 1
            }
        }
    }
    deinit { memoryTask?.cancel() }
    static func local() -> DiaryViewModel {
        let directory = DiaryLaunch.directory
        let processTime: @Sendable () -> Date = {
            #if DEBUG
            if CoachCorrectionUITestFixture.isEnabled { return CoachCorrectionUITestFixture.processInstant }
            #endif
            return Date()
        }
        return DiaryViewModel(store: DiaryStore(directory: directory, currentTime: processTime), sampleMode: DiaryLaunch.isSampleMode, preferences: DiaryLaunch.defaults,
            backup: FolderBackup(directory: directory.deletingLastPathComponent().appending(path: DiaryLaunch.isUITest ? "BackupSettings-" + (DiaryLaunch.testID?.uuidString ?? "test") : "BackupSettings", directoryHint: .isDirectory)))
    }
    var activeDay: TrackingDay? { readModel?.activeDay }
    var todaysMeals: [MealReadModel] { readModel?.meals.sorted { $0.capturedAt > $1.capturedAt } ?? [] }
    func meal(_ id: UUID) -> MealReadModel? { readModel?.meals.first { $0.id == id } ?? exactMeals[id] }
    func day(_ id: UUID) -> TrackingDay? { activeDay?.id == id ? activeDay : exactDays[id]?.day }
    func dayDetail(_ id: UUID) -> DiaryDayReadModel? { exactDays[id] }
    func loadMeal(_ id: UUID) async {
        guard let token = selection, !Task.isCancelled else { return }
        let generation = changeGeneration, request = UUID()
        if mealDetailRequests[id] == nil, mealDetailRequests.count >= 30 { mealDetailRequests = [:] }
        mealDetailRequests[id] = request
        func isCurrent() -> Bool {
            !Task.isCancelled && !isChangingProfile && selection == token && changeGeneration == generation && mealDetailRequests[id] == request
        }
        defer { if mealDetailRequests[id] == request { mealDetailRequests[id] = nil } }
        do {
            let value = try await mealDetailLoading(id, token.identity.profileID)
            try await store.validateSelectionOwnership(token)
            guard isCurrent() else { return }
            if exactMeals.count >= 30 { exactMeals = [:] }; exactMeals[id] = value
            await loadDay(value.dayID)
        } catch DiaryError.notFound { if isCurrent() { exactMeals[id] = nil } }
        catch { if isCurrent() { present(error) } }
    }
    func loadDay(_ id: UUID) async {
        guard let token = selection, !Task.isCancelled else { return }
        let generation = changeGeneration, request = UUID()
        if dayDetailRequests[id] == nil, dayDetailRequests.count >= 30 { dayDetailRequests = [:] }
        dayDetailRequests[id] = request
        func isCurrent() -> Bool {
            !Task.isCancelled && !isChangingProfile && selection == token && changeGeneration == generation && dayDetailRequests[id] == request
        }
        defer { if dayDetailRequests[id] == request { dayDetailRequests[id] = nil } }
        do {
            let value = try await dayDetailLoading(id, token.identity.profileID)
            guard isCurrent() else { return }; if exactDays.count >= 30 { exactDays = [:] }; exactDays[id] = value
        } catch { if isCurrent() { present(error) } }
    }
    func load(createDefaultProfile: Bool = true) async {
        guard beginProfileTransition() else { return }
        let previous = readModel?.head.profile.id
        defer { finishProfileTransition() }
        do {
            profiles = try await store.profiles()
            #if DEBUG
            if DiaryHistoryUITestFixture.isEnabled, profiles.isEmpty {
                _ = try await store.importProfile(DiaryHistoryUITestFixture.snapshot())
                profiles = try await store.profiles()
            }
            if ProgressUITestFixture.isEnabled, profiles.isEmpty {
                _ = try await store.importProfile(ProgressUITestFixture.snapshot())
                profiles = try await store.profiles()
            }
            if DiaryLaunch.isCoachHistoryFixture, profiles.isEmpty {
                _ = try await store.importProfile(CoachUITestInference.historySnapshot())
                profiles = try await store.profiles()
            }
            #endif
            if preferences?.bool(forKey: "diarySignedOut") == true { await clearProfileSelection(); return }
            if let profile = profiles.first(where: { $0.id.uuidString == preferences?.string(forKey: "diarySelectedProfile") }) ?? profiles.first {
                try await install(try await profileSelection(profile.id))
            } else if createDefaultProfile {
                try await install(try await store.createProfile(DiaryProfile(name: "My diary", language: DiaryLaunch.language, timeZoneID: deviceTimeZone().identifier)))
                profiles = try await store.profiles()
            }
        } catch { await recoverProfileSelection(previous); present(error) }
    }
    private func install(_ initial: DiaryReadModel) async throws {
        let owner = initial.head.profile.id, token = try await store.selectionOwnership(expectedProfileID: initial.head.profile.id)
        changesTask?.cancel()
        let stream = await store.changes(expectedProfileID: owner)
        let scope = DiaryPhotoScope(identity: token.identity, selectionEpoch: token.selectionEpoch)
        if let photoLoader { await photoLoader.reset(to: scope) }
        else {
            let store = store
            photoLoader = DiaryPhotoLoader(scope: scope, limiter: photoWorkLimiter, reader: { reference, scope in
                try await store.validateSelection(epoch: scope.selectionEpoch, expectedProfileID: scope.identity.profileID)
                guard try await store.diaryHead(expectedProfileID: scope.identity.profileID).timelineGeneration == scope.identity.timelineGeneration else { throw DiaryError.wrongOwner }
                let bytes = try await store.photoContent(reference, expectedProfileID: scope.identity.profileID)
                try await store.validateSelection(epoch: scope.selectionEpoch, expectedProfileID: scope.identity.profileID)
                guard try await store.diaryHead(expectedProfileID: scope.identity.profileID).timelineGeneration == scope.identity.timelineGeneration else { throw DiaryError.wrongOwner }
                return bytes
            })
        }
        let current = try await store.diaryReadModel(expectedProfileID: owner)
        let status = try await store.coachWorkStatus(expectedProfileID: owner)
        try await store.validateSelection(epoch: token.selectionEpoch, expectedProfileID: owner)
        selection = token; exactMeals = [:]; exactDays = [:]; savedMealID = nil; manualCaptureAttempt = nil
        photoRequestGeneration &+= 1; changeGeneration &+= 1
        readModel = current; workStatus = status
        #if DEBUG
        if CoachCorrectionUITestFixture.isEnabled { try CoachCorrectionUITestFixture.installAudit() }
        #endif
        await selectBackupProfile(owner); rememberSelection()
        changesTask = Task { [weak self] in
            for await changes in stream {
                guard let self, !Task.isCancelled, !self.isChangingProfile, self.selection == token else { return }
                do { try await self.refresh(profileID: owner, changes: changes) }
                catch { if !self.isChangingProfile, self.selection == token { self.present(error) } }
            }
        }
    }
    func refresh(profileID: UUID) async throws { try await refresh(profileID: profileID, changes: nil) }
    private func refresh(profileID: UUID, changes: DiaryChanges?) async throws {
        guard let token = selection, token.identity.profileID == profileID else { return }
        let updated = try await (changes == nil ? actionReadModelLoading(profileID) : subscriberReadModelLoading(profileID))
        guard !isChangingProfile, selection == token else { return }
        guard updated.head.timelineGeneration == token.identity.timelineGeneration,
              updated.head.revision >= (readModel?.head.revision ?? 0) else { return }
        if updated.head.revision == readModel?.head.revision { return }
        let status = try await store.coachWorkStatus(expectedProfileID: profileID)
        if let changes { await photoLoader?.invalidate(changes) }
        else { await photoLoader?.purgeForMemoryPressure() }
        var meals: [UUID: MealReadModel] = [:], days: [UUID: DiaryDayReadModel] = [:]
        for id in exactMeals.keys { do { meals[id] = try await store.meal(id: id, expectedProfileID: profileID) } catch DiaryError.notFound {} }
        for id in exactDays.keys { do { days[id] = try await store.diaryDay(id: id, expectedProfileID: profileID) } catch DiaryError.notFound {} }
        guard !isChangingProfile, selection == token, updated.head.revision >= (readModel?.head.revision ?? 0) else { return }
        photoRequestGeneration &+= 1; changeGeneration &+= 1
        readModel = updated; workStatus = status; exactMeals = meals; exactDays = days
        if let index = profiles.firstIndex(where: { $0.id == profileID }) { profiles[index] = updated.head.profile }
        queueBackup()
    }
    struct MorningRecap: Equatable { var previous: DiaryDaySummary; var target: Double? }
    /// The day before the active one, for the morning check-in on Today and Coach; nil on a diary's first day.
    private(set) var morningRecap: MorningRecap?
    func loadMorningRecap() async {
        guard let day = activeDay, let owner = readModel?.profile.id,
              let page = try? await store.diaryHistory(limit: 2, expectedProfileID: owner) else { morningRecap = nil; return }
        guard let previous = page.days.first(where: { $0.day.id != day.id && $0.day.localDate < day.localDate }) else { morningRecap = nil; return }
        let target = (try? await store.goal(on: previous.day.localDate, expectedProfileID: owner))??.targets.kcal
        if activeDay?.id == day.id { morningRecap = MorningRecap(previous: previous, target: target) }
    }
    /// Starts the new waking day once the cutoff has passed, so logging never has to ask which day.
    func rollOverDay(at: Date = Date()) async {
        guard !isChangingProfile, let token = selection, activeDay != nil,
              (try? await store.dayAssignment(at: at, expectedSelection: token, expectedProfileID: token.identity.profileID)) == .newDay else { return }
        await change { _ = try await store.startDay(at: at, expectedSelection: token, expectedProfileID: token.identity.profileID) }
    }
    /// The morning weigh-in records on the day that is already open; Pip nods once it is saved.
    func saveMorningWeight(kg: Double) async -> Bool {
        guard let token = selection else { return false }
        let saved = await change { _ = try await store.recordWeight(value: (kg * 10).rounded() / 10, startNewDay: false, expectedProfileID: token.identity.profileID) }
        if saved { companionHabitEvent = CompanionEvent(profileID: token.identity.profileID, operationID: UUID(), kind: .saved, committedAt: Date()) }
        return saved
    }
    @discardableResult func change(_ operation: () async throws -> Void) async -> Bool {
        guard !isChangingProfile, let token = selection else { return false }
        do {
            try await operation(); try await refresh(profileID: token.identity.profileID)
            return !Task.isCancelled && selection == token
        } catch { if selection == token { present(error) }; return false }
    }
    @discardableResult func acceptReview(mealID: UUID, submissionID: UUID, expectedProfileID: UUID, currentTime: () -> Date = Date.init) async -> Bool {
        guard selection?.identity.profileID == expectedProfileID else { return false }
        let prior = try? await store.meal(id: mealID, expectedProfileID: expectedProfileID)
        let fresh = prior?.submissions.contains { $0.id == submissionID && $0.state == .awaitingReview } == true
        let result = await change { try await store.acceptReview(mealID: mealID, submissionID: submissionID, expectedProfileID: expectedProfileID) }
        if result, fresh, companionReviewSubmissions[expectedProfileID, default: []].insert(submissionID).inserted {
            companionReviewEvent = CompanionEvent(profileID: expectedProfileID, operationID: submissionID, kind: .reviewed, committedAt: currentTime())
        }
        return result
    }
    func capture(_ draft: MealDraft, dayID: UUID, at: Date = Date(), dateOnly: Bool = false, photoPreparation: PhotoPreparation? = nil, expectedSelection: DiarySelectionOwnership? = nil) async -> Bool {
        if case .saved = await capture(draft, destination: .day(dayID, dateOnly: dateOnly), at: at,
                                      photoPreparation: photoPreparation, expectedSelection: expectedSelection) { return true }
        return false
    }
    func capture(_ draft: MealDraft, destination: DiaryCaptureDestination, at: Date = Date(), photoRole: PhotoRole = .unspecified,
                 photoPreparation: PhotoPreparation? = nil, expectedSelection: DiarySelectionOwnership? = nil) async -> DiaryCaptureResult {
        guard draft.isValid, photoPreparation?.canCapture != false, !isSaving, !isChangingProfile, let token = selection,
              expectedSelection == nil || expectedSelection == token, captureTask == nil else { return .failed }
        isSaving = true
        let endProtection = beginCaptureProtection()
        let task = Task {
            defer { endProtection(); isSaving = false }
            return await performCapture(draft, destination: destination, at: at, photoRole: photoRole, token: token)
        }
        captureTask = task
        defer { captureTask = nil }
        return await task.value
    }
    var hasCaptureInFlight: Bool { captureTask != nil }
    func waitForCapture() async { _ = await captureTask?.value }
    private func performCapture(_ draft: MealDraft, destination: DiaryCaptureDestination, at: Date, photoRole: PhotoRole,
                                token: DiarySelectionOwnership) async -> DiaryCaptureResult {
        var committedID: UUID?
        do {
            var attempt: CaptureAttempt
            if let prior = manualCaptureAttempt, prior.selection == token, prior.draft.submissionID == draft.submissionID {
                guard prior.draft == draft, prior.destination == destination, prior.photoRole == photoRole else { throw DiaryError.staleRevision }
                attempt = prior
            } else {
                let prior = try await store.capturedMeal(submissionID: draft.submissionID, expectedSelection: token, expectedProfileID: token.identity.profileID)
                guard selection == token, !isChangingProfile else { return .failed }
                let references = prior?.submissions.first { $0.id == draft.submissionID }?.photoIDs.compactMap { id in prior?.photos.first { $0.photoID == id } } ?? []
                let photos = draft.photos.enumerated().map { index, data in
                    if references.indices.contains(index) {
                        let reference = references[index]
                        return MealPhoto(id: reference.photoID, data: data, createdAt: reference.createdAt, role: reference.role)
                    }
                    return MealPhoto(data: data, role: photoRole)
                }
                attempt = CaptureAttempt(selection: token, draft: draft, destination: destination, photoRole: photoRole,
                                         at: at, photos: photos, isNew: prior == nil, resolvedDestination: nil)
                // A committed automatic capture must not create another day during reconciliation.
                if let prior, destination == .automatic || destination == .newDay {
                    attempt.resolvedDestination = .day(prior.dayID, dateOnly: false)
                }
                manualCaptureAttempt = attempt
            }
            if attempt.resolvedDestination == nil {
                switch destination {
                case .automatic:
                    switch try await captureDayAssignment(attempt.at, token) {
                    case .existing(let id): attempt.resolvedDestination = .day(id, dateOnly: false)
                    case .newDay:
                        let day = try await store.startDay(at: attempt.at, expectedSelection: token, expectedProfileID: token.identity.profileID)
                        attempt.resolvedDestination = .day(day.id, dateOnly: false)
                    }
                case .newDay:
                    let day = try await store.startDay(at: attempt.at, expectedSelection: token, expectedProfileID: token.identity.profileID)
                    attempt.resolvedDestination = .day(day.id, dateOnly: false)
                case .day, .meal: attempt.resolvedDestination = destination
                }
                manualCaptureAttempt = attempt
            }
            let saved: MealReadModel
            switch attempt.resolvedDestination {
            case .meal(let id):
                saved = try await store.correctMealProjection(mealID: id, text: draft.text, photos: attempt.photos, reviewFirst: draft.reviewFirst,
                    submissionID: draft.submissionID, forCoach: !sampleMode, at: attempt.at, expectedSelection: token, expectedProfileID: token.identity.profileID)
            case .day(let id, let dateOnly):
                saved = try await store.captureProjection(text: draft.text, photos: attempt.photos, reviewFirst: draft.reviewFirst,
                    dayID: id, at: attempt.at, dateOnly: dateOnly, submissionID: draft.submissionID, forCoach: !sampleMode,
                    expectedSelection: token, expectedProfileID: token.identity.profileID)
            default: throw DiaryError.invalidData
            }
            committedID = saved.id
            try await store.validateSelectionOwnership(token)
            guard selection == token, !isChangingProfile else { return .failed }
            savedMealID = saved.id
            if attempt.isNew, companionCaptureEvent?.profileID != token.identity.profileID || companionCaptureEvent?.operationID != draft.submissionID {
                captureReceipt = draft.submissionID
                companionCaptureEvent = CompanionEvent(profileID: token.identity.profileID, operationID: draft.submissionID, kind: .saved, committedAt: Date())
            }
            resumeWorker()
            var refreshNeeded = false
            do { try await refresh(profileID: token.identity.profileID) }
            catch { refreshNeeded = true }
            try await store.validateSelectionOwnership(token)
            guard selection == token, !isChangingProfile else { return .failed }
            await loadSavedMealIfNeeded(saved.id)
            // Concurrent diary changes can invalidate every detail read; one direct read still owns this receipt.
            var latest: MealReadModel?
            if meal(saved.id) == nil { latest = try? await mealDetailLoading(saved.id, token.identity.profileID) }
            try await store.validateSelectionOwnership(token)
            guard selection == token, !isChangingProfile else { return .failed }
            if let latest, meal(saved.id) == nil {
                if exactMeals.count >= 30 { exactMeals = [:] }
                exactMeals[saved.id] = latest
            }
            if meal(saved.id) == nil { refreshNeeded = true }
            if attempt.isNew, !refreshNeeded { noteFirstMealOfDay(saved, profileID: token.identity.profileID, operationID: draft.submissionID) }
            errorMessage = refreshNeeded ? "Saved on this iPhone. Reload the diary to refresh totals." : nil
            return .saved(saved.id)
        } catch {
            guard selection == token, !isChangingProfile else { return .failed }
            do { try await store.validateSelectionOwnership(token) }
            catch DiaryError.wrongOwner, DiaryError.noProfile { return .failed }
            catch { /* Storage failure does not prove that the selected owner changed. */ }
            if let committedID {
                errorMessage = "Saved on this iPhone. Reload the diary to refresh totals."
                return .saved(committedID)
            }
            present(error)
            return .failed
        }
    }
    /// Decided after the durable write, from refreshed state: a new meal that is the active day's only one.
    private func noteFirstMealOfDay(_ meal: MealReadModel, profileID: UUID, operationID: UUID) {
        guard meal.submissions.count == 1, readModel?.activeDay?.id == meal.dayID, readModel?.meals.map(\.id) == [meal.id],
              companionHabitEvent?.profileID != profileID || companionHabitEvent?.operationID != operationID else { return }
        companionHabitEvent = CompanionEvent(profileID: profileID, operationID: operationID, kind: .firstMealToday, committedAt: Date())
    }
    private func loadSavedMealIfNeeded(_ id: UUID) async {
        // One bounded retry when a newer projection invalidates an in-flight detail read.
        for _ in 0..<2 where meal(id) == nil && !Task.isCancelled {
            let generation = changeGeneration
            await loadMeal(id)
            if generation == changeGeneration { break }
        }
    }
    func saveManualNutrition(_ payload: ManualNutritionPayload,
                             expectedSelection: DiarySelectionOwnership) async -> ManualNutritionSaveResult? {
        guard !isSaving, !isChangingProfile, selection == expectedSelection,
              payload.profileID == expectedSelection.identity.profileID else { return nil }
        isSaving = true; defer { isSaving = false }
        manualDayChanged = false
        let generation = changeGeneration
        do {
            let result = try await manualNutritionSaving(payload, expectedSelection)
            try await store.validateSelectionOwnership(expectedSelection)
            guard !Task.isCancelled, selection == expectedSelection, !isChangingProfile else { return nil }
            var refreshNeeded = false
            do { try await refresh(profileID: payload.profileID) }
            catch { refreshNeeded = true }
            try await store.validateSelectionOwnership(expectedSelection)
            guard !Task.isCancelled, selection == expectedSelection, !isChangingProfile else { return nil }
            if changeGeneration == generation {
                if exactMeals.count >= 30 { exactMeals = [:] }
                exactMeals[result.meal.id] = result.meal
            } else { await loadSavedMealIfNeeded(result.meal.id) }
            try await store.validateSelectionOwnership(expectedSelection)
            guard !Task.isCancelled, selection == expectedSelection, !isChangingProfile else { return nil }
            if meal(result.meal.id) == nil { refreshNeeded = true }
            savedMealID = result.meal.id
            errorMessage = refreshNeeded ? "Saved on this iPhone. Reload the diary to refresh totals." : nil
            if !result.replayed, companionCaptureEvent?.operationID != result.submissionID {
                captureReceipt = result.submissionID
                companionCaptureEvent = CompanionEvent(profileID: payload.profileID, operationID: result.submissionID, kind: .saved, committedAt: Date())
            }
            if !result.replayed, !refreshNeeded { noteFirstMealOfDay(result.meal, profileID: payload.profileID, operationID: result.submissionID) }
            return result
        } catch {
            guard selection == expectedSelection, !isChangingProfile else { return nil }
            do { try await store.validateSelectionOwnership(expectedSelection) }
            catch DiaryError.wrongOwner, DiaryError.noProfile { return nil }
            catch { /* Storage failure does not prove that the selected owner changed. */ }
            if error as? DiaryError == .ambiguousDay { manualDayChanged = true } else { present(error) }
            return nil
        }
    }
    func switchProfile(_ id: UUID) async {
        guard beginProfileTransition() else { return }; let previous = readModel?.head.profile.id
        defer { finishProfileTransition() }
        do { try await install(try await profileSelection(id)) } catch { await recoverProfileSelection(previous); present(error) }
    }
    func createProfile(name: String) async {
        guard beginProfileTransition() else { return }; let previous = readModel?.head.profile.id
        defer { finishProfileTransition() }
        do { try await install(try await store.createProfile(DiaryProfile(name: name, timeZoneID: deviceTimeZone().identifier))); profiles = try await store.profiles() }
        catch { await recoverProfileSelection(previous); present(error) }
    }
    /// Only a readable, empty diary folder starts "My diary"; a failed read (locked phone, upgrade error) retries instead.
    @discardableResult func createFirstProfile() async -> Bool {
        do { profiles = try await store.profiles() } catch { present(error); return false }
        guard profiles.isEmpty else { await load(createDefaultProfile: false); return false }
        await createProfile(name: "My diary"); return readModel != nil
    }
    func signOut() async { guard beginProfileTransition() else { return }; defer { finishProfileTransition() }; await clearProfileSelection() }
    func deleteProfile(_ owner: UUID) async {
        guard beginProfileTransition() else { return }; defer { finishProfileTransition() }
        let selected = readModel?.head.profile.id == owner
        do {
            try await backup?.removeProfile(owner); try await store.deleteProfile(owner); preferences.map { CompanionLastActive(defaults: $0).forget(owner) }
            if selected { await clearProfileSelection() }
            profiles = try await store.profiles()
        } catch { present(error) }
        // The transition stopped the open diary's change stream and backup, so reattach them when it stays open.
        if let current = readModel {
            do { try await install(current) } catch { await recoverProfileSelection(current.head.profile.id); present(error) }
        }
    }
    private func beginProfileTransition() -> Bool {
        guard !isChangingProfile, !isSaving else { return false }; isChangingProfile = true; photoRequestGeneration &+= 1
        changesTask?.cancel(); cancelSampleWorker(); backupTask?.cancel(); backupRequested = nil; return true
    }
    private func finishProfileTransition() { isChangingProfile = false; queueBackup(); resumeWorker() }
    private func clearProfileSelection(rememberSignOut: Bool = true) async {
        await backup?.selectProfile(nil); await store.signOut()
        if let photoLoader { await photoLoader.purgeForMemoryPressure() }
        selection = nil; manualCaptureAttempt = nil; readModel = nil; exactMeals = [:]; exactDays = [:]; workStatus = CoachWorkStatus()
        photoRequestGeneration &+= 1; changeGeneration &+= 1
        backupGeneration = nil; backupStatus = FolderBackupStatus(); backupScheduledRevision = nil
        if rememberSignOut { preferences?.set(true, forKey: "diarySignedOut"); preferences?.removeObject(forKey: "diarySelectedProfile") }
    }
    private func recoverProfileSelection(_ previous: UUID?) async {
        if let previous { do { try await install(try await profileSelection(previous)); return } catch {} }
        // A failed read (locked phone, Snap It launch) is not a sign-out; the next read reopens the same diary.
        await clearProfileSelection(rememberSignOut: false)
    }
    private func rememberSelection() { if let id = readModel?.head.profile.id { preferences?.set(id.uuidString, forKey: "diarySelectedProfile"); preferences?.set(false, forKey: "diarySignedOut") } }
    func loadProfiles() async { guard !isChangingProfile else { return }; do { profiles = try await store.profiles() } catch { present(error) } }
    private func selectBackupProfile(_ profileID: UUID?) async {
        backupGeneration = nil; backupScheduledRevision = nil; backupRequested = nil
        await backup?.selectProfile(profileID)
        if let owner = profileID, let backup {
            do { backupGeneration = try await backup.generation(profileID: owner) } catch { backupStatus = FolderBackupStatus(pendingError: "Backup pending"); return }
            backupStatus = await backup.status(profileID: owner)
        } else { backupStatus = FolderBackupStatus() }
    }
    func queueBackup() {
        guard !isChangingProfile, let token = selection, let head = readModel?.head, backupStatus.configured,
              let generation = backupGeneration, backup != nil, backupScheduledRevision != head.revision else { return }
        backupRequested = (token, head.revision, generation); backupScheduledRevision = head.revision
        guard backupTask == nil || backupTask?.isCancelled == true else { return }
        let id = UUID(); backupTaskID = id
        backupTask = Task {
            defer { if backupTaskID == id { backupTask = nil; backupTaskID = nil } }
            while let pending = backupRequested, !Task.isCancelled {
                backupRequested = nil
                guard selection == pending.0, let backup else { return }
                let owner = pending.0.identity.profileID
                let status = await backup.status(profileID: owner)
                guard selection == pending.0, status.configured else { return }
                do {
                    let request = try await store.exportRequest(expectedProfileID: owner, backupGeneration: pending.2)
                    guard selection == pending.0, !Task.isCancelled else { return }
                    try await backup.save(request, coordinator: exportCoordinator)
                } catch {
                    guard selection == pending.0, !Task.isCancelled else { return }
                    backupStatus = await backup.status(profileID: owner)
                    if backupStatus.pendingError == nil { backupStatus.pendingError = "Backup pending" }
                    return
                }
                if selection == pending.0 { backupStatus = await backup.status(profileID: owner) }
            }
        }
    }
    func retryBackup() {
        backupScheduledRevision = nil
        queueBackup()
    }
    func waitForBackup() async { await backupTask?.value }
    func selectBackupFolder(_ url: URL) async {
        guard !isChangingProfile, let backup, let token = selection else { return }
        do {
            try await backup.selectFolder(url, profileID: token.identity.profileID)
            guard selection == token else { return }
            backupGeneration = try await backup.generation(profileID: token.identity.profileID)
            backupStatus = await backup.status(profileID: token.identity.profileID); backupScheduledRevision = nil; queueBackup()
        } catch { errorMessage = "Could not choose this backup folder. Your local diary is preserved." }
    }
    func importArchive(_ archive: DiarySnapshot) async -> Bool {
        guard beginProfileTransition() else { return false }; let previous = readModel?.head.profile.id
        defer { finishProfileTransition() }
        do {
            if profiles.contains(where: { $0.id == archive.profile.id }) {
                guard previous == archive.profile.id else { throw DiaryError.wrongOwner }
                try await store.restore(archive, expectedProfileID: archive.profile.id)
                try await install(try await store.diaryReadModel(expectedProfileID: archive.profile.id))
            } else { try await install(try await store.importProfile(archive)); profiles = try await store.profiles() }
            restoreGeneration += 1; return true
        } catch { await recoverProfileSelection(previous); present(error); return false }
    }
    private func cancelSampleWorker() { worker?.cancel(); worker = nil; workerID = nil; workerRerun = false }
    func enterBackground() { sampleProcessingAllowed = false; cancelSampleWorker() }
    func waitForWorker() async { await worker?.value }
    func resumeWorker(allowProcessing: Bool = false) {
        if allowProcessing { sampleProcessingAllowed = true }
        guard sampleMode else { resumeCoach?(); return }
        guard sampleProcessingAllowed, !isChangingProfile, let token = selection else { return }
        // A capture committed while the worker runs may miss its queue read, so the worker goes around once more.
        guard worker == nil else { workerRerun = true; return }
        let id = UUID(); workerID = id
        worker = Task {
            defer { if workerID == id { worker = nil; workerID = nil } }
            do {
                repeat {
                    workerRerun = false
                    try Task.checkCancellation(); try await store.processPending(expectedProfileID: token.identity.profileID); try Task.checkCancellation(); try await refresh(profileID: token.identity.profileID)
                } while workerRerun
            } catch is CancellationError {} catch { if selection == token { present(error) } }
        }
    }
    private func present(_ error: Error) { errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save on this iPhone. Your input is still here." }
}

enum DiaryLaunch {
    static func shouldLaunchDiary(arguments: [String], environment: [String: String]) -> Bool {
        guard environment["XCTestConfigurationFilePath"] != nil else { return true }
        guard let index = arguments.firstIndex(of: "--diary-ui-test"), arguments.indices.contains(index + 1) else { return false }
        return UUID(uuidString: arguments[index + 1]) != nil
    }
    static var shouldLaunchDiary: Bool {
        shouldLaunchDiary(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
    }
    /// UI-test and sample launch switches exist only in Debug builds, so Release has no hidden modes.
    static var testID: UUID? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--diary-ui-test"), args.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: args[index + 1])
        #else
        return nil
        #endif
    }
    static var isUITest: Bool { testID != nil }
    /// UI tests run at any wall-clock time, so fixtures keep their day unless a test asks for the rollover.
    static var rollsOverDays: Bool { !isUITest || ProcessInfo.processInfo.arguments.contains("--rollover-ui-test") }
    #if DEBUG
    static var isCoachHistoryFixture: Bool { isCoachUITest && ProcessInfo.processInfo.arguments.contains("--coach-history-fixture") }
    #endif
    static var isCoachUITest: Bool { isUITest && ProcessInfo.processInfo.arguments.contains("--coach-ui-test") }
    static var isCoachInferenceFixture: Bool { isCoachUITest && ProcessInfo.processInfo.arguments.contains("--coach-inference-fixture") }
    static var isSampleMode: Bool {
        #if DEBUG
        (isUITest && !isCoachUITest) || ProcessInfo.processInfo.arguments.contains("--sample-mode")
        #else
        false
        #endif
    }
    static var defaults: UserDefaults {
        if let id = testID, let defaults = UserDefaults(suiteName: "MivuUITest-" + id.uuidString) { return defaults }
        return .standard
    }
    static var language: String { "en" }
    static var directory: URL {
        if let id = testID { return URL.temporaryDirectory.appending(path: "MivuUITest-" + id.uuidString, directoryHint: .isDirectory) }
        return URL.documentsDirectory.appending(path: "Diary", directoryHint: .isDirectory)
    }
}

struct DiaryPreferencesDraft {
    var timezone = TimeZone.current.identifier
    var preferences = ""
    private var profileID: UUID?
    private var synchronizedRestoreGeneration: Int?
    private var savedTimezone = TimeZone.current.identifier
    private var savedPreferences = ""
    private(set) var timezoneConflict = false
    private(set) var preferencesConflict = false
    var hasConflict: Bool { timezoneConflict || preferencesConflict }
    var isDirty: Bool { timezone != savedTimezone || preferences != savedPreferences }

    mutating func synchronize(_ profile: DiaryProfile?, restoreGeneration: Int) {
        if profileID != profile?.id || synchronizedRestoreGeneration != restoreGeneration {
            profileID = profile?.id; synchronizedRestoreGeneration = restoreGeneration
            useSaved(profile)
            return
        }
        let currentTimezone = profile?.timeZoneID ?? TimeZone.current.identifier
        let currentPreferences = profile?.preferences ?? ""
        if currentTimezone != savedTimezone {
            if timezone == savedTimezone || timezone == currentTimezone { timezone = currentTimezone; timezoneConflict = false }
            else { timezoneConflict = true }
            savedTimezone = currentTimezone
        }
        if currentPreferences != savedPreferences {
            if preferences == savedPreferences || preferences == currentPreferences { preferences = currentPreferences; preferencesConflict = false }
            else { preferencesConflict = true }
            savedPreferences = currentPreferences
        }
    }
    mutating func useSaved(_ profile: DiaryProfile?) {
        timezone = profile?.timeZoneID ?? TimeZone.current.identifier
        preferences = profile?.preferences ?? ""
        savedTimezone = timezone; savedPreferences = preferences
        timezoneConflict = false; preferencesConflict = false
    }
    func conflicts(with profile: DiaryProfile) -> Bool {
        hasConflict || (timezone != savedTimezone && profile.timeZoneID != savedTimezone && profile.timeZoneID != timezone)
            || (preferences != savedPreferences && profile.preferences != savedPreferences && profile.preferences != preferences)
    }
    func applying(to profile: DiaryProfile) -> DiaryProfile {
        var updated = profile
        if !timezoneConflict && timezone != savedTimezone { updated.timeZoneID = timezone }
        if !preferencesConflict && preferences != savedPreferences { updated.preferences = preferences }
        return updated
    }
}
