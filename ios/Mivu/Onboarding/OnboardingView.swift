import SwiftUI

/// Pip asks a few questions, ChatGPT turns them into daily targets, and accepting saves the profile, weight and goal.
/// Runs after a first diary is created and again from Settings, prefilled with what is saved.
struct OnboardingView: View {
    @Bindable var model: DiaryViewModel
    @Bindable var connection: ChatGPTConnection
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable { case hello, height, weight, birthYear, sex, target, pace, diet, connect, results }
    static let dietChoices = ["Gluten-free", "Lactose-free", "Vegetarian", "Vegan", "Type 1 diabetes", "Type 2 diabetes", "Crohn's", "IBS", "Nut allergy"]
    private static let thisYear = Calendar.current.component(.year, from: Date())
    private static let kgPerLb = 0.45359237

    @State private var step = Step.hello
    @State private var heightCm: Double?
    @State private var weightKg: Double?
    @State private var targetKg: Double?
    @State private var birthYear: Int?
    @State private var about = ProfileAbout(heightCm: 0, birthYear: 0)
    @State private var metricHeight = true
    @State private var metricWeight = true
    @State private var targets = NutritionValues()
    @State private var reply: OnboardingTargets.Reply?
    @State private var asking = false
    @State private var askFailed = false
    @State private var saving = false
    @State private var window: UIWindow?
    @State private var runtime = CompanionRuntime()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(model: DiaryViewModel, connection: ChatGPTConnection, onFinish: @escaping () -> Void) {
        self.model = model
        self.connection = connection
        self.onFinish = onFinish
        let saved = model.readModel
        if let about = saved?.profile.about {
            _about = State(initialValue: about)
            _heightCm = State(initialValue: about.heightCm)
            _birthYear = State(initialValue: about.birthYear)
        }
        if let weight = saved?.weight { _weightKg = State(initialValue: weight.unit == "lb" ? weight.value * Self.kgPerLb : weight.value) }
        _targetKg = State(initialValue: saved?.activeGoal?.goalWeightKg)
    }

    private var answers: OnboardingAnswers? {
        guard let heightCm, let weightKg, let targetKg, let birthYear else { return nil }
        var about = about
        about.heightCm = heightCm; about.birthYear = birthYear
        return OnboardingAnswers(about: about, weightKg: weightKg, targetKg: targetKg)
    }

    var body: some View {
        VStack(spacing: 0) {
            CompanionView(presentation: CompanionOutput(pose: .resting, playback: reduceMotion ? .staticPose : .animated, reactionID: nil, nextDeadline: nil),
                          darkMode: colorScheme == .dark, size: 150, runtime: runtime)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { card }
                    .padding(20).frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            buttons.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Color.diaryCanvas.ignoresSafeArea())
        .background(PresentationWindowReader { window = $0 })
        .task {
            await runtime.select(CharacterCatalog.bundled.resolve("pip"))
            await runtime.attach(eligible: true)
            react(.greeting)
        }
        .onDisappear { runtime.stop() }
        .onChange(of: connection.planAuthorized && connection.models.contains { $0.slug == connection.selectedModel }) { _, ready in
            if ready && step == .connect { advance() }
        }
    }

    // MARK: Questions

    @ViewBuilder private var card: some View {
        switch step {
        case .hello:
            title("Hi, I'm Pip!", "A few quick questions, and I'll work out daily targets that fit you.")
        case .height:
            title("How tall are you?")
            unitPicker($metricHeight, "cm", "ft")
            if metricHeight {
                numberField("Height", value: $heightCm, unit: "cm")
            } else {
                HStack {
                    numberField("Feet", value: feet, unit: "ft")
                    numberField("Inches", value: inches, unit: "in")
                }
            }
        case .weight:
            title("What do you weigh now?")
            unitPicker($metricWeight, "kg", "lb")
            numberField("Weight", value: shownWeight($weightKg), unit: metricWeight ? "kg" : "lb")
        case .birthYear:
            title("What year were you born?")
            TextField("Birth year", value: $birthYear, format: .number.grouping(.never))
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder).font(.title2)
                .accessibilityIdentifier("onboardingBirthYear")
        case .sex:
            title("Which should I use for the calorie formula?", "It changes the estimate a little. Skipping uses the middle.")
            Picker("Sex", selection: $about.sex) {
                Text("Female").tag(ProfileAbout.Sex.female)
                Text("Male").tag(ProfileAbout.Sex.male)
                Text("Prefer not to say").tag(ProfileAbout.Sex.unspecified)
            }.pickerStyle(.inline).labelsHidden()
        case .target:
            title("What weight are you aiming for?", "Enter your current weight to keep it.")
            unitPicker($metricWeight, "kg", "lb")
            numberField("Target weight", value: shownWeight($targetKg), unit: metricWeight ? "kg" : "lb")
        case .pace:
            title("How fast should we go?")
            Picker("Pace", selection: $about.pace) {
                Text(metricWeight ? "Gentle · 0.25 kg a week" : "Gentle · ½ lb a week").tag(ProfileAbout.Pace.gentle)
                Text(metricWeight ? "Steady · 0.5 kg a week" : "Steady · 1 lb a week").tag(ProfileAbout.Pace.steady)
                Text(metricWeight ? "Faster · 0.75 kg a week" : "Faster · 1½ lb a week").tag(ProfileAbout.Pace.faster)
            }.pickerStyle(.inline).labelsHidden()
        case .diet:
            title("Anything about how you eat?", "Coach keeps this in mind for every suggestion.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(Self.dietChoices, id: \.self) { tag in
                    let chosen = about.dietTags.contains(tag)
                    Button { if chosen { about.dietTags.removeAll { $0 == tag } } else { about.dietTags.append(tag) } } label: {
                        Label(tag, systemImage: chosen ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered).tint(chosen ? .diaryAccent : .secondary)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            TextField("Anything else? Allergies, intolerances, dislikes", text: $about.healthNotes, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                .onChange(of: about.healthNotes) { _, text in if text.count > 2_000 { about.healthNotes = String(text.prefix(2_000)) } }
        case .connect:
            title("Let's ask ChatGPT", "Connect your ChatGPT account and it will tune your targets. Your answers stay on this iPhone except for this request.")
            if connection.isConnecting { ProgressView("Connecting") }
            if let notice = connection.notice { Text(notice.rawValue).font(.subheadline).foregroundStyle(Color.diarySecondary) }
        case .results:
            results
        }
    }

    @ViewBuilder private var results: some View {
        title("Your daily targets")
        if asking {
            Label("ChatGPT is checking these…", systemImage: "sparkles").foregroundStyle(Color.diarySecondary)
        } else if reply == nil {
            Label("Estimate from a standard formula", systemImage: "function").foregroundStyle(Color.diarySecondary)
        }
        numberField("Calories", labeled: true, value: $targets.kcal, unit: "kcal").disabled(asking)
        numberField("Protein", labeled: true, value: $targets.protein, unit: "g").disabled(asking)
        numberField("Carbs", labeled: true, value: $targets.carbs, unit: "g").disabled(asking)
        numberField("Fat", labeled: true, value: $targets.fat, unit: "g").disabled(asking)
        if let reply { Text(reply.explanation).foregroundStyle(Color.diarySecondary) }
        if askFailed {
            Text("ChatGPT couldn't answer just now. You can keep the estimate or try again.").foregroundStyle(Color.diarySecondary)
            Button("Try ChatGPT again") { Task { await askChatGPT() } }.frame(minHeight: 44)
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button { primary() } label: {
                Text(primaryTitle).font(.headline).contentTransition(.identity).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
            .disabled(!canContinue).accessibilityIdentifier("onboardingNext")
            switch step {
            case .hello: Button("Set up later") { onFinish() }.frame(minHeight: 44).accessibilityIdentifier("onboardingLater")
            case .connect: Button("Skip, use the estimate") { advance() }.frame(minHeight: 44).accessibilityIdentifier("onboardingSkipConnect")
            case .sex, .diet: Button("Skip") { advance() }.frame(minHeight: 44)
            default: EmptyView()
            }
            if step != .hello && step != .results {
                Button("Back") { back() }.frame(minHeight: 44).font(.subheadline)
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .hello: "Let's start"
        case .connect: connection.activeRegistrationID == nil ? "Continue with ChatGPT" : "Reauthorize ChatGPT"
        case .results: "Save targets"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .height: heightCm.map { (50...272).contains($0) } ?? false
        case .weight: weightKg.map { (20...400).contains($0) } ?? false
        case .target: targetKg.map { (20...400).contains($0) } ?? false
        case .birthYear: birthYear.map { (1900...Self.thisYear - 13).contains($0) } ?? false
        case .connect: window != nil && !connection.isConnecting && !connection.isDisconnecting
        case .results: !asking && !saving && [targets.kcal, targets.protein, targets.carbs, targets.fat].allSatisfy { ($0 ?? -1) >= 0 }
        default: true
        }
    }

    // MARK: Flow

    private func primary() {
        switch step {
        case .connect: if let window { Task { await connection.connect(window: window) } }
        case .results: Task { await save() }
        default: advance()
        }
    }

    private func advance() {
        var next = Step(rawValue: step.rawValue + 1) ?? .results
        if next == .pace, answers?.keepsWeight == true { next = .diet }
        if next == .connect, connection.planAuthorized { next = .results }
        step = next
        if next == .results { showEstimate() } else { react(step == .height ? .attentive : .saved) }
    }

    private func back() {
        var previous = Step(rawValue: step.rawValue - 1) ?? .hello
        if previous == .pace, answers?.keepsWeight == true { previous = .target }
        step = previous
    }

    private func showEstimate() {
        guard let answers else { return }
        targets = answers.estimate(); reply = nil; askFailed = false
        if connection.planAuthorized { Task { await askChatGPT() } } else { react(.saved) }
    }

    private func askChatGPT() async {
        guard let answers else { return }
        asking = true; askFailed = false
        react(.thinking)
        do {
            let respond = try connection.inference()
            let result = try await respond(OnboardingTargets.input(answers, estimate: answers.estimate()), nil)
            guard let parsed = OnboardingTargets.parse(result.text) else { throw ResponsesClient.Failure.malformedResponse }
            reply = parsed; targets = parsed.targets
            react(.saved)
        } catch {
            askFailed = true
            react(.recovery)
        }
        asking = false
    }

    private func save() async {
        guard let answers, let profile = model.readModel?.profile else { return }
        saving = true
        var updated = profile
        updated.about = answers.about
        let today = ProgressDate.label(Date(), zone: profile.timeZoneID), targets = targets
        let savedWeight = model.readModel?.weight.map { $0.unit == "lb" ? $0.value * Self.kgPerLb : $0.value }
        let saved = await model.change {
            try await model.store.updateProfile(updated, expectedProfile: profile, expectedProfileID: profile.id)
            if savedWeight.map({ abs($0 - answers.weightKg) >= 0.05 }) ?? true {
                _ = try await model.store.recordWeight(value: (answers.weightKg * 10).rounded() / 10, expectedProfileID: profile.id)
            }
            let existing = try await model.store.goal(on: today, exact: true, expectedProfileID: profile.id)
            let goal = GoalRecord(id: existing?.id ?? UUID(), effectiveLocalDate: today, timeZoneID: profile.timeZoneID, targets: targets,
                                  goalWeightKg: (answers.targetKg * 10).rounded() / 10, exerciseCreditEnabled: existing?.exerciseCreditEnabled ?? false)
            _ = try await model.store.setGoals(goal, expectedRevision: existing?.revision, expectedProfileID: profile.id)
        }
        saving = false
        if saved { onFinish() }
    }

    private func react(_ pose: CompanionPose) {
        let output = CompanionOutput(pose: pose, playback: reduceMotion ? .staticPose : .animated, reactionID: UUID(), nextDeadline: nil)
        Task { await runtime.apply(output, darkMode: colorScheme == .dark) }
    }

    // MARK: Fields

    private func title(_ text: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.title.bold()).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).foregroundStyle(Color.diarySecondary) }
        }
    }

    private func unitPicker(_ metric: Binding<Bool>, _ metricUnit: String, _ imperialUnit: String) -> some View {
        Picker("Units", selection: metric) {
            Text(metricUnit).tag(true)
            Text(imperialUnit).tag(false)
        }.pickerStyle(.segmented).frame(maxWidth: 200)
    }

    private func numberField(_ label: String, labeled: Bool = false, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            if labeled { Text(label).frame(minWidth: 80, alignment: .leading) }
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).font(.title2)
            Text(unit).foregroundStyle(Color.diarySecondary)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("\(label) in \(unit)")
    }

    /// Weight shown in the chosen unit, stored in kg.
    private func shownWeight(_ kg: Binding<Double?>) -> Binding<Double?> {
        Binding(get: { kg.wrappedValue.map { metricWeight ? $0 : (($0 / Self.kgPerLb) * 10).rounded() / 10 } },
                set: { kg.wrappedValue = $0.map { metricWeight ? $0 : $0 * Self.kgPerLb } })
    }

    private var feet: Binding<Double?> {
        Binding(get: { heightCm.map { (($0 / 2.54).rounded() / 12).rounded(.down) } },
                set: { heightCm = (($0 ?? 0) * 12 + (inches.wrappedValue ?? 0)) * 2.54 })
    }

    private var inches: Binding<Double?> {
        Binding(get: { heightCm.map { ($0 / 2.54).rounded().truncatingRemainder(dividingBy: 12) } },
                set: { heightCm = ((feet.wrappedValue ?? 0) * 12 + ($0 ?? 0)) * 2.54 })
    }
}
