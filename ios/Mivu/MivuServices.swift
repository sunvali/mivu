import UIKit

/// The process's one diary, connection and Coach, shared by the screens and the Siri action,
/// so a Siri prompt and the Coach tab never run two workers on the same diary.
@MainActor final class MivuServices {
    static let shared = MivuServices.local()

    let diary: DiaryViewModel
    let connection: ChatGPTConnection
    let coach: CoachViewModel
    let nutritionKeys: NutritionAPIKeyStore
    let inbox: CoachInbox
    private var loading: Task<Void, Never>?
    private var starting: Task<Void, Never>?
    private var backgroundLease: UIBackgroundTaskIdentifier = .invalid

    init(diary: DiaryViewModel, connection: ChatGPTConnection, coach: CoachViewModel, nutritionKeys: NutritionAPIKeyStore,
         inbox: CoachInbox = .local) {
        self.diary = diary; self.connection = connection; self.coach = coach; self.nutritionKeys = nutritionKeys; self.inbox = inbox
    }

    private static func local() -> MivuServices {
        // UI tests never reach a live model, so the host Mac's Apple Intelligence cannot change their flows.
        var appleModelAvailable = ChatGPTConnection.appleIntelligenceAvailable
        if DiaryLaunch.isUITest { appleModelAvailable = { false } }
        let diary = DiaryViewModel.local(), session = ChatGPTConnection(preferences: DiaryLaunch.defaults, appleModelAvailable: appleModelAvailable)
        let keys = NutritionAPIKeyStore.local
        let foodSource = FoodEvidenceClient()
        let fixture: (() throws -> CoachViewModel.Inference)? = DiaryLaunch.isCoachInferenceFixture
            ? { { input, tools in try await CoachUITestInference.respond(input, tools) } } : nil
        let coach = CoachViewModel(diary: diary, connection: session, inference: fixture, lookup: { query in
            try await foodSource.search(query: query, apiKey: keys.load())
        })
        return MivuServices(diary: diary, connection: session, coach: coach, nutritionKeys: keys)
    }

    /// Loads the selected diary once; later calls wait for the first.
    func loadDiary(createDefaultProfile: Bool) async {
        if loading == nil {
            loading = Task { [diary, coach] in
                diary.resumeCoach = { coach.resume() }
                diary.retryCoachMeal = { id in Task { await coach.retryMeal(id) } }
                await diary.load(createDefaultProfile: createDefaultProfile)
            }
        }
        await loading?.value
    }

    /// Loads the diary, restores the connection, starts the Coach worker and captures waiting Siri prompts, once.
    func start(createDefaultProfile: Bool) async {
        await loadDiary(createDefaultProfile: createDefaultProfile)
        if starting == nil {
            starting = Task { [connection, coach, inbox] in
                if !DiaryLaunch.isUITest { await connection.restore() }
                coach.startMonitoring(); coach.resume()
                await coach.drainInbox(inbox)
            }
        }
        await starting?.value
    }

    /// Keeps the Coach worker running after the app leaves the screen; onExpire runs if iOS ends the time first.
    func continueCoachInBackground(onExpire: @escaping @MainActor () -> Void = {}) {
        coach.continueInBackground(begin: { expire in
            backgroundLease = UIApplication.shared.beginBackgroundTask(withName: "Finish saved meal") {
                onExpire()
                expire() // handler runs on the main actor and must end the task before returning
            }
            return backgroundLease != .invalid
        }, end: { [weak self] in
            guard let self, backgroundLease != .invalid else { return }
            let lease = backgroundLease; backgroundLease = .invalid
            UIApplication.shared.endBackgroundTask(lease)
        })
    }
    func endCoachBackground() { coach.endBackgroundLease() }
}
