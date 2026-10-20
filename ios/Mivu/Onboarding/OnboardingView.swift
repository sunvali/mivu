import SwiftUI

/// Pip asks a few questions, ChatGPT turns them into daily targets, and accepting saves the profile, weight and goal.
/// Runs after a first diary is created and again from Settings, prefilled with what is saved.
struct OnboardingView: View {
    @Bindable var model: DiaryViewModel
    @Bindable var connection: ChatGPTConnection
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable { case hello, about, goal, diet, connect, results }
    private enum Field: Hashable { case height, feet, inches, weight, birthYear, target, notes }
    static let dietChoices = ["Gluten-free", "Lactose-free", "Vegetarian", "Vegan", "Type 1 diabetes", "Type 2 diabetes", "Crohn's", "IBS", "Nut allergy"]
    private static let thisYear = Calendar.current.component(.year, from: Date())
    private static let kgPerLb = 0.45359237

    @State private var step = Step.hello
    @State private var askSharingConsent = false
    @State private var forward = true
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
    @State private var savedCount = 0
    @State private var window: UIWindow?
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CompanionView(presentation: CompanionOutput(pose: .resting, playback: reduceMotion ? .staticPose : .animated, reactionID: nil, nextDeadline: nil),
                                  darkMode: colorScheme == .dark, size: typeSize.isAccessibilitySize || focus != nil ? 72 : 140, runtime: runtime)
                        .animation(.snappy, value: focus == nil)
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
            .safeAreaInset(edge: .bottom) { if focus == nil { actions } }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(PresentationWindowReader { window = $0 })
        .openAIConsent(isPresented: $askSharingConsent, connection: connection) { connectChatGPT() }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: savedCount)
        .task {
            await runtime.select(CharacterCatalog.bundled.resolve("pip"))
            await runtime.attach(eligible: true)
            react(.greeting)
        }
        .onDisappear { runtime.stop() }
        .onChange(of: connection.planAuthorized && connection.models.contains { $0.slug == connection.selectedModel }) { _, ready in
            if ready && step == .connect { go(to: .results) }
        }
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
            if step == .diet { Button("Skip") { advance() } }
        }
        ToolbarItemGroup(placement: .keyboard) {
            if let next = nextField {
                Button("Next") { focus = next }.accessibilityIdentifier("keyboardNext")
            }
            Spacer()
            Button("Done") { focus = nil }.fontWeight(.semibold).accessibilityIdentifier("keyboardDone")
        }
    }

    /// The keyboard's Next walks the About card in reading order.
    private var nextField: Field? {
        switch focus {
        case .height, .inches: .weight
        case .feet: .inches
        case .weight: .birthYear
        default: nil
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Button { primary() } label: {
                Group {
                    if saving || (asking && step == .results) { ProgressView().tint(Color.diaryActionText) } else { Text(primaryTitle) }
                }
                .font(.headline).contentTransition(.identity).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
            .disabled(!canContinue).accessibilityIdentifier("onboardingNext")
            if step == .connect {
                Button("Use the estimate instead") { go(to: .results) }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44).accessibilityIdentifier("onboardingSkipConnect")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .frame(maxWidth: 560)
    }

    private var primaryTitle: String {
        switch step {
        case .hello: "Get started"
        case .connect: connection.activeRegistrationID == nil ? "Continue with ChatGPT" : "Reauthorize ChatGPT"
        case .results: "Save my targets"
        default: "Continue"
        }
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch step {
        case .hello:
            header("Hi, I'm Pip", "Answer a few quick questions and I'll set daily targets that fit you. It takes about a minute.")
            card {
                promise("ruler", "Your body and goal", "Height, weight and where you want to be.")
                Divider()
                promise("leaf", "How you eat", "Diets, allergies or conditions Coach should know.")
                Divider()
                promise("sparkles", "Targets that fit", "ChatGPT tunes calories, protein, carbs and fat.")
            }
        case .about:
            header("About you", "Used only to estimate your energy needs.")
            card {
                row("Height", invalid: heightCm.map { !(50...272).contains($0) } ?? false) {
                    if metricHeight {
                        numberField($heightCm, field: .height, id: "onboardingHeight")
                    } else {
                        numberField(feet, field: .feet, id: "onboardingFeet", width: 44)
                        Text("ft").foregroundStyle(Color.diarySecondary)
                        numberField(inches, field: .inches, id: "onboardingInches", width: 44)
                    }
                    unitMenu($metricHeight, metric: "cm", imperial: "in")
                }
                Divider()
                row("Weight", invalid: weightKg.map { !(20...400).contains($0) } ?? false) {
                    numberField(shownWeight($weightKg), field: .weight, id: "onboardingWeight")
                    unitMenu($metricWeight, metric: "kg", imperial: "lb")
                }
                Divider()
                row("Birth year", invalid: birthYear.map { !(1900...Self.thisYear - 13).contains($0) } ?? false) {
                    TextField("Add", value: $birthYear, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).font(.title3.monospacedDigit())
                        .focused($focus, equals: .birthYear).frame(maxWidth: 90)
                        .accessibilityLabel("Birth year").accessibilityIdentifier("onboardingBirthYear")
                }
                Divider()
                row("Sex", invalid: false) {
                    Picker("Sex", selection: $about.sex) {
                        Text("Female").tag(ProfileAbout.Sex.female)
                        Text("Male").tag(ProfileAbout.Sex.male)
                        Text("Prefer not to say").tag(ProfileAbout.Sex.unspecified)
                    }.labelsHidden().tint(.diaryAccent).fixedSize()
                }
            }
            footnote("Sex is optional. Skipping it uses the midpoint of both formulas.")
        case .goal:
            header("Your goal", "Enter your current weight to keep it.")
            card {
                row("Target weight", invalid: targetKg.map { !(20...400).contains($0) } ?? false) {
                    numberField(shownWeight($targetKg), field: .target, id: "onboardingTarget")
                    unitMenu($metricWeight, metric: "kg", imperial: "lb")
                }
            }
            if let answers, !answers.targetIsHealthy {
                footnote("That target is below a healthy weight for your height, so Mivu can't set it. Choose a higher target, or talk to a doctor or registered dietitian.")
            } else if let answers, !answers.keepsWeight {
                Text(answers.targetKg < answers.weightKg ? "How quickly would you like to lose it?" : "How quickly would you like to gain it?")
                    .font(.headline).padding(.top, 4)
                card {
                    ForEach(ProfileAbout.Pace.allCases, id: \.self) { pace in
                        if pace != .gentle { Divider() }
                        paceRow(pace)
                    }
                }
            } else if answers != nil {
                Label("We'll aim to keep your weight steady.", systemImage: "equal.circle.fill")
                    .foregroundStyle(Color.diarySecondary)
            }
        case .diet:
            header("How do you eat?", "Pick anything that applies. Coach keeps it in mind for every suggestion.")
            FlowLayout(spacing: 8) {
                ForEach(Self.dietChoices, id: \.self) { chip($0) }
            }
            card {
                TextField("Other allergies, intolerances or dislikes", text: $about.healthNotes, axis: .vertical)
                    .lineLimit(2...5).focused($focus, equals: .notes)
                    .onChange(of: about.healthNotes) { _, text in if text.count > 2_000 { about.healthNotes = String(text.prefix(2_000)) } }
            }
        case .connect:
            header("Let ChatGPT tune it", "Connect your ChatGPT account to turn your answers into personal targets.")
            card {
                promise("lock.shield", "Private by default", "Only these answers are sent, once. Your diary stays on this iPhone.")
                Divider()
                promise("person.crop.circle.badge.checkmark", "Your own plan", "Uses your ChatGPT plan's allowance. No extra cost.")
            }
            if connection.isConnecting { ProgressView("Waiting for ChatGPT…").frame(maxWidth: .infinity) }
            if let notice = connection.notice { footnote(notice.rawValue) }
        case .results:
            header("Your daily targets", nil)
            results
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 16) {
                    status
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calories").font(.subheadline.weight(.medium)).foregroundStyle(Color.diarySecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("0", value: $targets.kcal, format: .number.precision(.fractionLength(0)))
                                .keyboardType(.numberPad).font(.system(size: energySize, weight: .semibold, design: .rounded).monospacedDigit())
                                .fixedSize().accessibilityLabel("Calories per day")
                            Text("kcal a day").font(.title3.weight(.medium)).foregroundStyle(Color.diarySecondary)
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
            }
            if askFailed {
                VStack(alignment: .leading, spacing: 8) {
                    footnote("ChatGPT couldn't answer just now. You can keep the estimate or try again.")
                    Button("Try again", systemImage: "arrow.clockwise") { Task { await askChatGPT() } }
                        .buttonStyle(.glass).tint(.diaryAccent).frame(minHeight: 44)
                }
            }
            footnote("These are estimates, not medical advice. Check with a doctor or registered dietitian before big changes to how you eat, especially if you have a health condition. You can change targets any time in Settings › Goals.")
        }
    }

    @ViewBuilder private var macros: some View {
        macro("Protein", $targets.protein, .diaryProtein)
        macro("Carbs", $targets.carbs, .diaryCarbs)
        macro("Fat", $targets.fat, .diaryFat)
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
        case .about:
            heightCm.map { (50...272).contains($0) } == true && weightKg.map { (20...400).contains($0) } == true
                && birthYear.map { (1900...Self.thisYear - 13).contains($0) } == true
        case .goal: targetKg.map { (20...400).contains($0) } == true && answers?.targetIsHealthy == true
        case .connect: window != nil && !connection.isConnecting && !connection.isDisconnecting
        case .results: !asking && !saving && [targets.kcal, targets.protein, targets.carbs, targets.fat].allSatisfy { ($0 ?? -1) >= 0 }
        default: true
        }
    }

    private func primary() {
        switch step {
        case .connect: if connection.sharingConsented { connectChatGPT() } else { askSharingConsent = true }
        case .results: Task { await save() }
        default: advance()
        }
    }

    private func connectChatGPT() {
        if let window { Task { await connection.connect(window: window) } }
    }

    private func advance() {
        var next = Step(rawValue: step.rawValue + 1) ?? .results
        if next == .connect, connection.planAuthorized { next = .results }
        go(to: next)
    }

    private func back() {
        var previous = Step(rawValue: step.rawValue - 1) ?? .hello
        if previous == .connect, connection.planAuthorized { previous = .diet }
        go(to: previous)
    }

    private func go(to next: Step) {
        focus = nil
        forward = next.rawValue > step.rawValue
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) { step = next }
        switch next {
        case .about: react(.attentive); if heightCm == nil { focus = metricHeight ? .height : .feet }
        case .goal: react(.saved); if targetKg == nil { focus = .target }
        case .results: if forward { showEstimate() }
        default: if forward { react(.saved) }
        }
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
        let today = ProgressDate.label(Date(), zone: profile.timeZoneID), targets = targets
        let savedWeight = model.readModel?.weight.map { $0.unit == "lb" ? $0.value * Self.kgPerLb : $0.value }
        let saved = await model.change {
            // The stored profile, not the cached one: Coach may have edited it, or a failed save already wrote `about`.
            let latest = try await model.store.diaryHead(expectedProfileID: profile.id).profile
            var updated = latest
            updated.about = answers.about
            try await model.store.updateProfile(updated, expectedProfile: latest, expectedProfileID: profile.id)
            if savedWeight.map({ abs($0 - answers.weightKg) >= 0.05 }) ?? true {
                _ = try await model.store.recordWeight(value: (answers.weightKg * 10).rounded() / 10, expectedProfileID: profile.id)
            }
            let existing = try await model.store.goal(on: today, exact: true, expectedProfileID: profile.id)
            let goal = GoalRecord(id: existing?.id ?? UUID(), effectiveLocalDate: today, timeZoneID: profile.timeZoneID, targets: targets,
                                  goalWeightKg: (answers.targetKg * 10).rounded() / 10, exerciseCreditEnabled: existing?.exerciseCreditEnabled ?? false)
            _ = try await model.store.setGoals(goal, expectedRevision: existing?.revision, expectedProfileID: profile.id)
        }
        saving = false
        if saved { savedCount += 1; onFinish() }
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

    /// A ledger row: label left, value and unit right, with a hint under the label when the value is out of range.
    private func row(_ label: String, invalid: Bool, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if invalid { Text("Check this value").font(.caption).foregroundStyle(Color.diaryError) }
            }
            Spacer(minLength: 8)
            value()
        }
        .frame(minHeight: 56)
    }

    private func numberField(_ value: Binding<Double?>, field: Field, id: String, width: CGFloat = 90) -> some View {
        TextField("Add", value: value, format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(.title3.monospacedDigit())
            .focused($focus, equals: field).frame(maxWidth: width).accessibilityIdentifier(id)
    }

    private func unitMenu(_ metric: Binding<Bool>, metric metricUnit: String, imperial imperialUnit: String) -> some View {
        Menu {
            Picker("Unit", selection: metric) {
                Text(metricUnit).tag(true)
                Text(imperialUnit == "in" ? "ft, in" : imperialUnit).tag(false)
            }
        } label: {
            HStack(spacing: 2) {
                Text(metric.wrappedValue ? metricUnit : imperialUnit)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(Color.diaryAccent).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Unit, \(metric.wrappedValue ? metricUnit : imperialUnit)")
    }

    private func paceRow(_ pace: ProfileAbout.Pace) -> some View {
        let name: String = switch pace { case .gentle: "Gentle"; case .steady: "Steady"; case .faster: "Faster" }
        let amount = metricWeight ? "\(pace.kgPerWeek.formatted()) kg a week"
            : "\((pace.kgPerWeek / Self.kgPerLb).formatted(.number.precision(.fractionLength(1)))) lb a week"
        let note: String = switch pace { case .gentle: "Easiest to keep up"; case .steady: "Right for most people"; case .faster: "Takes more discipline" }
        let chosen = about.pace == pace
        return Button { withAnimation(.snappy) { about.pace = pace } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) · \(amount)").fontWeight(chosen ? .semibold : .regular).foregroundStyle(Color.diaryText)
                    Text(note).font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(chosen ? Color.diaryAccent : Color.diaryRule)
            }
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: chosen)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    private func chip(_ tag: String) -> some View {
        let chosen = about.dietTags.contains(tag)
        return Button {
            withAnimation(.snappy) { if chosen { about.dietTags.removeAll { $0 == tag } } else { about.dietTags.append(tag) } }
        } label: {
            HStack(spacing: 6) {
                if chosen { Image(systemName: "checkmark").font(.footnote.weight(.bold)) }
                Text(tag)
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

/// Wraps chips onto as many lines as they need.
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
