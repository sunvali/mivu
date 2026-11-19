import SwiftUI

/// Pip asks one question per screen, shows formula targets at once, and ChatGPT can tune them on the last screen.
/// Accepting saves the profile, weight and goal. Runs after a first diary is created and again from Settings, prefilled.
struct OnboardingView: View {
    @Bindable var model: DiaryViewModel
    @Bindable var connection: ChatGPTConnection
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable { case hello, height, weight, birthYear, sex, goal, pace, diet, results }
    private enum Field: Hashable { case height, weight, target, notes }
    static let dietChoices = ["Gluten-free", "Lactose-free", "Vegetarian", "Vegan", "Type 1 diabetes", "Type 2 diabetes", "Crohn's", "IBS", "Nut allergy"]
    private static let thisYear = Calendar.current.component(.year, from: Date())
    private static let kgPerLb = 0.45359237

    @State private var step = Step.hello
    @State private var askSharingConsent = false
    @State private var forward = true
    // Height and weights are typed text in the shown unit; values are stored metric.
    @State private var heightText: String
    @State private var weightText: String
    @State private var targetText: String
    @State private var birthYear: Int
    @State private var sexChosen: Bool
    @State private var about: ProfileAbout
    @State private var metricHeight: Bool
    @State private var metricWeight: Bool
    @State private var targets = NutritionValues()
    @State private var reply: OnboardingTargets.Reply?
    @State private var asking = false
    @State private var askFailed = false
    @State private var saving = false
    @State private var savedCount = 0
    @State private var runtime = CompanionRuntime()
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var energySize = 48.0

    init(model: DiaryViewModel, connection: ChatGPTConnection, onFinish: @escaping () -> Void) {
        self.model = model
        self.connection = connection
        self.onFinish = onFinish
        let saved = model.readModel
        let imperial = Locale.current.measurementSystem == .us
        let savedAbout = saved?.profile.about
        let weightKg = saved?.weight.map { $0.unit == "lb" ? $0.value * Self.kgPerLb : $0.value } ?? 70
        let metricWeight = saved?.weight.map { $0.unit != "lb" } ?? !imperial
        _about = State(initialValue: savedAbout ?? ProfileAbout(heightCm: 170, birthYear: Self.thisYear - 30))
        _sexChosen = State(initialValue: savedAbout != nil)
        _birthYear = State(initialValue: savedAbout?.birthYear ?? Self.thisYear - 30)
        _metricHeight = State(initialValue: !imperial)
        _metricWeight = State(initialValue: metricWeight)
        _heightText = State(initialValue: Self.heightText(savedAbout?.heightCm ?? 170, metric: !imperial))
        _weightText = State(initialValue: Self.weightText(weightKg, metric: metricWeight))
        _targetText = State(initialValue: saved?.activeGoal?.goalWeightKg.map { Self.weightText($0, metric: metricWeight) } ?? "")
    }

    // MARK: Values

    private static func heightText(_ cm: Double, metric: Bool) -> String {
        String(Int((metric ? cm : cm / 2.54).rounded()))
    }
    private static func weightText(_ kg: Double, metric: Bool) -> String {
        (((metric ? kg : kg / kgPerLb) * 10).rounded() / 10).formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }
    private var heightCm: Double? { ProgressDate.number(heightText).map { metricHeight ? $0 : $0 * 2.54 } }
    private func kg(_ text: String) -> Double? { ProgressDate.number(text).map { metricWeight ? $0 : $0 * Self.kgPerLb } }
    private var weightKg: Double? { kg(weightText) }
    private var targetKg: Double? { kg(targetText) }
    private var heightValid: Bool { heightCm.map { (50...272).contains($0) } == true }
    private func weightValid(_ kg: Double?) -> Bool { kg.map { (20...400).contains($0) } == true }

    private var answers: OnboardingAnswers? {
        guard let heightCm, let weightKg else { return nil }
        var about = about
        about.heightCm = heightCm; about.birthYear = birthYear
        return OnboardingAnswers(about: about, weightKg: weightKg, targetKg: targetKg ?? weightKg)
    }

    private static func feetAndInches(_ inches: Double) -> String {
        let total = Int(inches.rounded())
        return "\(total / 12)′ \(total % 12)″"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CompanionView(presentation: CompanionOutput(pose: .resting, playback: reduceMotion ? .staticPose : .animated, reactionID: nil, nextDeadline: nil),
                                  darkMode: colorScheme == .dark, size: pipSize, runtime: runtime)
                        .animation(.snappy, value: pipSize)
                    VStack(alignment: .leading, spacing: 20) { page }
                        .id(step)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                                                          removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.diaryCanvas.ignoresSafeArea())
            // Done sits above the keyboard here, not in a keyboard toolbar: that toolbar goes
            // missing when setup is presented over Settings, and the number pad has no return key.
            .safeAreaInset(edge: .bottom) { if focus == nil { actions } else { keyboardBar } }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .openAIConsent(isPresented: $askSharingConsent, connection: connection) { connectChatGPT() }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: savedCount)
        .task {
            await runtime.select(CharacterCatalog.bundled.resolve("pip"))
            await runtime.attach(eligible: true)
            react(.greeting)
        }
        .onDisappear { runtime.stop() }
        // Connecting from the targets screen asks ChatGPT as soon as the account is ready.
        .onChange(of: connection.tunesTargets && connection.models.contains { $0.slug == connection.selectedModel }) { _, ready in
            if ready && step == .results && reply == nil && !asking { Task { await askChatGPT() } }
        }
    }

    private var pipSize: CGFloat {
        if typeSize.isAccessibilitySize || focus != nil { return 64 }
        return step == .hello ? 140 : step == .pace || step == .diet || step == .results ? 72 : 104
    }

    // MARK: Chrome

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if step == .hello {
                Button("Later") { onFinish() }.accessibilityIdentifier("onboardingLater")
            } else {
                Button { back() } label: { Image(systemName: "chevron.backward") }.accessibilityLabel("Back")
            }
        }
        ToolbarItem(placement: .principal) {
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .tint(.diaryAccent).frame(width: 140)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if step == .sex { Button("Skip") { about.sex = .unspecified; sexChosen = true; advance() }.accessibilityIdentifier("onboardingSkip") }
            if step == .diet { Button("Skip") { advance() }.accessibilityIdentifier("onboardingSkip") }
        }
    }

    private var keyboardBar: some View {
        HStack {
            Spacer()
            Button("Done") { focus = nil }.fontWeight(.semibold).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("keyboardDone")
        }
        .padding(.horizontal, 20).background(.bar)
    }

    @ViewBuilder private var actions: some View {
        // Sex advances on a card tap, so it has no Continue.
        if step != .sex {
            VStack(spacing: 8) {
                // At accessibility sizes the bar would cover the targets, so Tune moves into the page.
                if step == .results, showsTune, !typeSize.isAccessibilitySize { tuneButton }
                Button { primary() } label: {
                    Group {
                        if saving { ProgressView().tint(Color.diaryActionText) } else { Text(primaryTitle) }
                    }
                    .font(.headline).contentTransition(.identity).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
                .disabled(!canContinue).accessibilityIdentifier("onboardingNext")
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxWidth: 560)
        }
    }

    private var tuneButton: some View {
        VStack(spacing: 8) {
            Button { tune() } label: {
                Group {
                    if connection.isConnecting { ProgressView() } else { Label("Tune with ChatGPT", systemImage: "sparkles") }
                }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.glass).tint(.diaryAccent)
            .disabled(connection.isConnecting || connection.isDisconnecting || asking || saving)
            .accessibilityIdentifier("onboardingTune")
            Text("Shares your answers with ChatGPT after you agree.")
                .font(.caption).foregroundStyle(Color.diarySecondary).multilineTextAlignment(.center)
        }
    }

    /// ChatGPT can still tune these numbers: not yet tuned, and an account that can connect.
    private var showsTune: Bool { reply == nil && !connection.tunesTargets && !connection.planNotEligible }

    private var primaryTitle: String {
        switch step {
        case .hello: String(localized: "Get started")
        case .results: String(localized: "Save my targets")
        default: String(localized: "Continue")
        }
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch step {
        case .hello:
            header(String(localized: "Hi, I'm Pip"), String(localized: "Answer a few quick questions and I'll set daily targets that fit you. It takes about a minute."))
            card {
                promise("ruler", String(localized: "Your body and goal"), String(localized: "Height, weight and where you want to be."))
                Divider()
                promise("leaf", String(localized: "How you eat"), String(localized: "Diets, allergies or conditions Coach should know."))
                Divider()
                promise("sparkles", String(localized: "Targets that fit"), String(localized: "Calories, protein, carbs and fat in seconds. ChatGPT can fine-tune them."))
            }
        case .height:
            question(String(localized: "How tall are you?"), nil)
            if metricHeight {
                MeasureRuler(title: String(localized: "Height"), text: $heightText, range: 90...250, step: 1, unit: shown("cm"),
                             placeholder: 170, fieldID: "onboardingHeight", focus: $focus, field: .height)
            } else {
                MeasureRuler(title: String(localized: "Height"), text: $heightText, range: 36...96, step: 1, unit: "",
                             placeholder: 67, fieldID: "onboardingHeight", focus: $focus, field: .height,
                             formatted: Self.feetAndInches, majorEvery: 12)
            }
            unitPicker(String(localized: "Height unit", comment: "Accessibility name of the cm or feet and inches switch"), metric: $metricHeight, metricLabel: shown("cm"),
                       imperialLabel: String(localized: "ft, in", comment: "Feet and inches, a height unit")) { metric in
                if let cm = ProgressDate.number(heightText).map({ metric ? $0 * 2.54 : $0 }) { heightText = Self.heightText(cm, metric: metric) }
            }
            if !heightValid { invalidNote }
        case .weight:
            question(String(localized: "What do you weigh?"), nil)
            weightRuler(String(localized: "Weight"), text: $weightText, id: "onboardingWeight", field: .weight, placeholder: weightKg ?? 70)
            weightUnitPicker
            if !weightValid(weightKg) { invalidNote }
        case .birthYear:
            question(String(localized: "When were you born?"), String(localized: "Your age changes how much energy you burn."))
            Picker("Birth year", selection: $birthYear) {
                ForEach(1900...Self.thisYear - 13, id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.wheel).frame(maxWidth: .infinity)
            .accessibilityIdentifier("onboardingBirthYear")
        case .sex:
            question(String(localized: "Your sex", comment: "Onboarding question title"), String(localized: "Optional. Helps estimate the energy you burn."))
            VStack(spacing: 10) {
                sexCard(.female, String(localized: "Female"))
                sexCard(.male, String(localized: "Male"))
                sexCard(.unspecified, String(localized: "Prefer not to say"))
            }
            Text("Prefer not to say uses the midpoint of both formulas.").font(.footnote).foregroundStyle(Color.diarySecondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        case .goal:
            question(String(localized: "What's your goal weight?"), nil)
            weightRuler(String(localized: "Goal weight", comment: "Accessibility name of the goal weight ruler"), text: $targetText, id: "onboardingTarget", field: .target, placeholder: targetKg ?? weightKg ?? 70)
            if let answers, weightValid(targetKg), !answers.targetIsHealthy {
                footnote(String(localized: "That target is below a healthy weight for your height, so Mivu can't set it. Choose a higher target, or talk to a doctor or registered dietitian."))
            } else if let answers, weightValid(targetKg) {
                Text(goalCaption(answers)).font(.headline).foregroundStyle(Color.diaryAccent).frame(maxWidth: .infinity)
            } else { invalidNote }
        case .pace:
            question(String(localized: "How active, and how fast?"), nil)
            Text("Day to day, you're…").font(.headline)
            VStack(spacing: 8) { ForEach(ProfileAbout.Activity.allCases, id: \.self) { activityCard($0) } }
            if let answers, !answers.keepsWeight {
                Text(answers.targetKg < answers.weightKg ? String(localized: "How quickly would you like to lose it?") : String(localized: "How quickly would you like to gain it?"))
                    .font(.headline).padding(.top, 4)
                card {
                    ForEach(ProfileAbout.Pace.allCases, id: \.self) { pace in
                        if pace != .gentle { Divider() }
                        paceRow(pace, answers)
                    }
                }
                if ProfileAbout.Pace.allCases.contains(where: { atFloor($0, answers) }) {
                    footnote(String(localized: "Mivu won't go below \(answers.floor.formatted()) kcal a day."))
                }
            } else {
                Label("We'll aim to keep your weight steady.", systemImage: "equal.circle.fill").foregroundStyle(Color.diarySecondary)
            }
        case .diet:
            question(String(localized: "How do you eat?"), nil)
            Text("Right now", comment: "Onboarding heading above the pregnancy or breastfeeding choice").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diarySecondary)
            chip(OnboardingAnswers.pregnancyTag)
            if about.dietTags.contains(OnboardingAnswers.pregnancyTag) {
                Label {
                    Text("Mivu will aim to keep your weight steady. Your doctor or midwife is the best guide for how much to eat right now.")
                } icon: { Image(systemName: "heart.fill").foregroundStyle(Color.diaryAccent) }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.diarySummarySurface))
            }
            Text("Diet and health").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diarySecondary)
            FlowLayout(spacing: 8) {
                ForEach(Self.dietChoices, id: \.self) { chip($0) }
            }
            card {
                TextField("Other allergies, intolerances or dislikes", text: $about.healthNotes, axis: .vertical)
                    .lineLimit(2...5).focused($focus, equals: .notes)
                    .onChange(of: about.healthNotes) { _, text in if text.count > 2_000 { about.healthNotes = String(text.prefix(2_000)) } }
            }
        case .results:
            question(String(localized: "Your daily targets"), nil)
            results
        }
    }

    private func question(_ title: String, _ detail: String?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).foregroundStyle(Color.diarySecondary) }
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private var invalidNote: some View {
        Text("Check this value").font(.subheadline).foregroundStyle(Color.diaryError).frame(maxWidth: .infinity)
    }

    private func weightRuler(_ title: String, text: Binding<String>, id: String, field: Field, placeholder kg: Double) -> some View {
        MeasureRuler(title: title, text: text, range: metricWeight ? 30...250 : 66...550, step: 0.1, unit: shown(metricWeight ? "kg" : "lb"),
                     placeholder: ((metricWeight ? kg : kg / Self.kgPerLb) * 10).rounded() / 10, fieldID: id, focus: $focus, field: field)
    }

    private var weightUnitPicker: some View {
        unitPicker(String(localized: "Weight unit", comment: "Accessibility name of the kg or lb switch"), metric: $metricWeight, metricLabel: shown("kg"), imperialLabel: shown("lb")) { metric in
            for text in [$weightText, $targetText] {
                if let value = ProgressDate.number(text.wrappedValue) { text.wrappedValue = Self.weightText(metric ? value * Self.kgPerLb : value, metric: metric) }
            }
        }
    }

    /// A segmented unit switch that converts the typed value when it changes.
    private func unitPicker(_ title: String, metric: Binding<Bool>, metricLabel: String, imperialLabel: String, convert: @escaping (Bool) -> Void) -> some View {
        Picker(title, selection: Binding(get: { metric.wrappedValue }, set: { metric.wrappedValue = $0; convert($0) })) {
            Text(metricLabel).tag(true)
            Text(imperialLabel).tag(false)
        }
        .pickerStyle(.segmented).frame(maxWidth: 200).frame(maxWidth: .infinity)
    }

    private func goalCaption(_ answers: OnboardingAnswers) -> String {
        guard !answers.keepsWeight else { return String(localized: "Keep my weight") }
        let difference = abs(answers.targetKg - answers.weightKg) / (metricWeight ? 1 : Self.kgPerLb)
        let amount = "\(difference.formatted(.number.precision(.fractionLength(0...1)))) \(shown(metricWeight ? "kg" : "lb"))"
        return answers.targetKg < answers.weightKg ? String(localized: "\(amount) to lose", comment: "Goal weight caption: how much weight is left to lose") : String(localized: "\(amount) to gain", comment: "Goal weight caption: how much weight is left to gain")
    }

    private func sexCard(_ sex: ProfileAbout.Sex, _ name: String) -> some View {
        let chosen = sexChosen && about.sex == sex
        return Button {
            about.sex = sex; sexChosen = true
            advance()
        } label: {
            HStack {
                Text(name).font(.headline).foregroundStyle(Color.diaryText)
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "chevron.forward")
                    .foregroundStyle(chosen ? Color.diaryAccent : Color.diarySecondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 18).frame(minHeight: 56).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 16).fill(chosen ? Color.diarySummarySurface : Color.diarySurface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(chosen ? Color.diaryAccent : Color.diaryRule, lineWidth: chosen ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("onboardingSex-\(sex.rawValue)")
    }

    private func activityCard(_ activity: ProfileAbout.Activity) -> some View {
        let name: String = switch activity {
        case .sitting: String(localized: "Mostly sitting", comment: "Onboarding activity level option")
        case .some: String(localized: "On my feet some", comment: "Onboarding activity level option")
        case .active: String(localized: "Very active", comment: "Onboarding activity level option")
        }
        let chosen = (about.activity ?? .some) == activity
        return Button { withAnimation(.snappy) { about.activity = activity } } label: {
            HStack {
                Text(name).fontWeight(chosen ? .semibold : .regular).foregroundStyle(Color.diaryText)
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(chosen ? Color.diaryAccent : Color.diaryRule).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 14).fill(chosen ? Color.diarySummarySurface : Color.diarySurface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(chosen ? Color.diaryAccent : Color.diaryRule, lineWidth: chosen ? 2 : 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: chosen)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("onboardingActivity-\(activity.rawValue)")
    }

    private func atFloor(_ pace: ProfileAbout.Pace, _ answers: OnboardingAnswers) -> Bool {
        answers.targetKg < answers.weightKg && answers.estimate(pace).kcal == answers.floor
    }

    private func paceRow(_ pace: ProfileAbout.Pace, _ answers: OnboardingAnswers) -> some View {
        let name: String = switch pace { case .gentle: String(localized: "Gentle"); case .steady: String(localized: "Steady"); case .faster: String(localized: "Faster") }
        let kgPerWeek = answers.weeklyKg(pace)
        let amount = metricWeight ? String(localized: "\(kgPerWeek.formatted(.number.precision(.fractionLength(0...2)))) kg a week")
            : String(localized: "\((kgPerWeek / Self.kgPerLb).formatted(.number.precision(.fractionLength(1)))) lb a week")
        let kcal = (answers.estimate(pace).kcal ?? 0).formatted()
        let detail = answers.goalDate(pace).map {
            String(localized: "\(kcal) kcal a day · by \($0.formatted(.dateTime.month(.wide).year()))")
        } ?? String(localized: "\(kcal) kcal a day")
        let chosen = about.pace == pace
        return Button { withAnimation(.snappy) { about.pace = pace } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) · \(amount)").fontWeight(chosen ? .semibold : .regular).foregroundStyle(Color.diaryText)
                    Text(detail).font(.subheadline).foregroundStyle(atFloor(pace, answers) ? Color.diaryWarning : Color.diarySecondary)
                }
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(chosen ? Color.diaryAccent : Color.diaryRule).accessibilityHidden(true)
            }
            .frame(minHeight: 60).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: chosen)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("onboardingPace-\(pace.rawValue)")
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 16) {
                    status
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calories").font(.subheadline.weight(.medium)).foregroundStyle(Color.diarySecondary)
                        // Stacked at accessibility sizes so the unit never wraps letter by letter.
                        let energy = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                        energy {
                            TextField("0", value: $targets.kcal, format: .number.precision(.fractionLength(0)))
                                .keyboardType(.numberPad).font(.system(size: energySize, weight: .semibold, design: .rounded).monospacedDigit())
                                .fixedSize().accessibilityLabel("Calories per day")
                            Text("kcal a day").font(.title3.weight(.medium)).foregroundStyle(Color.diarySecondary)
                            if !typeSize.isAccessibilitySize {
                                Spacer(minLength: 0)
                                Image(systemName: "pencil").foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
                            }
                        }
                    }
                    Divider()
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) { macros }
                    } else {
                        HStack(spacing: 12) { macros }
                    }
                }
                .disabled(asking)
            }
            if let reply {
                Label { Text(reply.explanation) } icon: { Image(systemName: "sparkles").foregroundStyle(Color.diaryAccent) }
                    .foregroundStyle(Color.diaryText)
            } else if let answers {
                Text(basis(answers)).foregroundStyle(Color.diarySecondary)
            }
            if askFailed {
                VStack(alignment: .leading, spacing: 8) {
                    footnote(String(localized: "ChatGPT couldn't answer just now. You can keep the estimate or try again."))
                    Button("Try again", systemImage: "arrow.clockwise") { Task { await askChatGPT() } }
                        .buttonStyle(.glass).tint(.diaryAccent).frame(minHeight: 44)
                }
            }
            if let notice = connection.notice { footnote(String(localized: String.LocalizationValue(notice.rawValue))) }
            if showsTune, typeSize.isAccessibilitySize { tuneButton }
            footnote(String(localized: "These are estimates, not medical advice. Check with a doctor or registered dietitian before big changes to how you eat, especially if you have a health condition. You can change targets any time in Settings › Goals."))
        }
    }

    /// What the estimate is built from, so the number isn't a black box.
    private func basis(_ answers: OnboardingAnswers) -> String {
        let activity: String = switch answers.about.activity ?? .some {
        case .sitting: String(localized: "mostly sitting")
        case .some: String(localized: "on your feet some")
        case .active: String(localized: "very active")
        }
        if answers.holdsWeight { return String(localized: "Based on your body and being \(activity), to keep your weight steady. Tap a number to change it.") }
        guard let date = answers.goalDate(answers.about.pace) else { return String(localized: "Based on your body and being \(activity). Tap a number to change it.") }
        return String(localized: "Based on your body and being \(activity). At this pace you'd reach your goal around \(date.formatted(.dateTime.month(.wide).year())). Tap a number to change it.")
    }

    @ViewBuilder private var macros: some View {
        macro(String(localized: "Protein"), $targets.protein, .diaryProtein)
        macro(String(localized: "Carbs"), $targets.carbs, .diaryCarbs)
        macro(String(localized: "Fat"), $targets.fat, .diaryFat)
    }

    @ViewBuilder private var status: some View {
        if asking {
            Label { Text("ChatGPT is tuning your targets…") } icon: { ProgressView().controlSize(.small) }
                .font(.subheadline).foregroundStyle(Color.diarySecondary)
        } else {
            Label(reply == nil ? "Estimate" : "Tuned by ChatGPT", systemImage: reply == nil ? "function" : "sparkles")
                .font(.footnote.weight(.semibold)).foregroundStyle(Color.diaryAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.diaryAccent.opacity(0.12)))
        }
    }

    // MARK: Flow

    private var canContinue: Bool {
        switch step {
        case .height: heightValid
        case .weight: weightValid(weightKg)
        case .goal: weightValid(targetKg) && answers?.targetIsHealthy == true
        case .results: !asking && !saving && [targets.kcal, targets.protein, targets.carbs, targets.fat].allSatisfy { ($0 ?? -1) >= 0 }
        default: true
        }
    }

    private func primary() {
        if step == .results { Task { await save() } } else { advance() }
    }

    private func tune() {
        connection.provider = .chatGPT
        // Already signed in (Apple was the chosen provider): switching is enough, and the ready check asks ChatGPT.
        guard !connection.planAuthorized else { return }
        if connection.sharingConsented { connectChatGPT() } else { askSharingConsent = true }
    }

    private func connectChatGPT() {
        Task { await connection.connect() }
    }

    private func advance() { go(to: Step(rawValue: step.rawValue + 1) ?? .results) }
    private func back() { go(to: Step(rawValue: step.rawValue - 1) ?? .hello) }

    private func go(to next: Step) {
        focus = nil
        forward = next.rawValue > step.rawValue
        if next == .goal, targetText.isEmpty { targetText = weightText }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) { step = next }
        switch next {
        case .height: react(.attentive)
        case .results: if forward { showEstimate() }
        default: if forward { react(.saved) }
        }
    }

    private func showEstimate() {
        guard let answers else { return }
        targets = answers.estimate(); reply = nil; askFailed = false
        if connection.tunesTargets { Task { await askChatGPT() } } else { react(.saved) }
    }

    private func askChatGPT() async {
        guard let answers else { return }
        asking = true; askFailed = false
        react(.thinking)
        do {
            let respond = try connection.inference()
            let result = try await respond(OnboardingTargets.input(answers, estimate: answers.estimate()), nil)
            guard let parsed = OnboardingTargets.parse(result.text, floor: answers.floor) else { throw ResponsesClient.Failure.malformedResponse }
            withAnimation { reply = parsed; targets = parsed.targets }
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
        let targets = targets
        let savedWeight = model.readModel?.weight.map { $0.unit == "lb" ? $0.value * Self.kgPerLb : $0.value }
        let saved = await model.change {
            try await Self.saveSetup(answers, targets: targets, savedWeightKg: savedWeight, profile: profile, store: model.store)
        }
        saving = false
        if saved { savedCount += 1; onFinish() }
    }

    static func saveSetup(_ answers: OnboardingAnswers, targets: NutritionValues, savedWeightKg savedWeight: Double?,
                          profile: DiaryProfile, store: DiaryStore, at now: Date = Date()) async throws {
        let today = wakingDateLabel(now, zone: profile.timeZoneID) // The waking day Today reads, not the calendar date.
        // The stored profile, not the cached one: Coach may have edited it, or a failed save already wrote `about`.
        let latest = try await store.diaryHead(expectedProfileID: profile.id).profile
        var updated = latest
        updated.about = answers.about
        try await store.updateProfile(updated, expectedProfile: latest, expectedProfileID: profile.id)
        if savedWeight.map({ abs($0 - answers.weightKg) >= 0.05 }) ?? true {
            _ = try await store.recordWeight(value: (answers.weightKg * 10).rounded() / 10, at: now, expectedProfileID: profile.id)
        }
        let existing = try await store.goal(on: today, exact: true, expectedProfileID: profile.id)
        let goal = GoalRecord(id: existing?.id ?? UUID(), effectiveLocalDate: today, timeZoneID: profile.timeZoneID, targets: targets,
                              goalWeightKg: (answers.targetKg * 10).rounded() / 10, exerciseCreditEnabled: existing?.exerciseCreditEnabled ?? false)
        _ = try await store.setGoals(goal, expectedRevision: existing?.revision, expectedProfileID: profile.id)
    }

    private func react(_ pose: CompanionPose) {
        let output = CompanionOutput(pose: pose, playback: reduceMotion ? .staticPose : .animated, reactionID: UUID(), nextDeadline: nil)
        Task { await runtime.apply(output, darkMode: colorScheme == .dark) }
    }

    // MARK: Pieces

    private func header(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).foregroundStyle(Color.diarySecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }.modifier(DiarySummaryCardStyle())
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Color.diarySecondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.diaryAccent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12).accessibilityElement(children: .combine)
    }

    /// The units are fixed values; this is how they read on screen.
    private func shown(_ unit: String) -> String {
        switch unit {
        case "cm": String(localized: "cm", comment: "Centimetres, a height unit")
        case "in": String(localized: "in", comment: "Inches, a height unit")
        default: WeightEntry.shownUnit(unit)
        }
    }

    private func chip(_ tag: String) -> some View {
        let chosen = about.dietTags.contains(tag)
        return Button {
            withAnimation(.snappy) { if chosen { about.dietTags.removeAll { $0 == tag } } else { about.dietTags.append(tag) } }
        } label: {
            HStack(spacing: 6) {
                if chosen { Image(systemName: "checkmark").font(.footnote.weight(.bold)) }
                Text(LocalizedStringKey(tag)) // The tag itself is stored and sent to the model in English.
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14).frame(minHeight: 44)
            .foregroundStyle(chosen ? Color.diaryActionText : Color.diaryText)
            .background(Capsule().fill(chosen ? Color.diaryAccent : Color.diarySurface))
            .overlay(Capsule().strokeBorder(chosen ? Color.clear : Color.diaryRule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: chosen)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    private func macro(_ name: String, _ value: Binding<Double?>, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(name) } icon: { Circle().fill(color).frame(width: 8, height: 8) }
                .font(.subheadline.weight(.medium)).foregroundStyle(Color.diarySecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad).font(.title2.weight(.semibold).monospacedDigit()).fixedSize()
                    .accessibilityLabel("\(name) grams")
                Text("g").foregroundStyle(Color.diarySecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Weight shown in the chosen unit, stored in kg.
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(width: bounds.width, subviews)
        for (view, point) in zip(subviews, placed.points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + line))
    }
}
