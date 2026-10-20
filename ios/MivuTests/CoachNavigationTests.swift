import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct CoachNavigationTests {
    @Test(arguments: [false, true])
    func firstDiaryOrSourceSeekLoadsExactTargetWithoutPrewarming(sourceLink: Bool) async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        let trace = NavigationPageTrace(), store = f.diary.store
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), timelinePageLoading: { request, token in
            await trace.record(request)
            return try await store.coachPage(request, expectedSelection: token)
        })
        #expect(coach.timeline == nil)
        coach.draft = MealDraft(text: "Before the first Coach mount", photos: [Data([1, 2, 3])])
        let draft = coach.draft, attachments = coach.attachmentDraft.attachments
        let head = try await store.diaryHead(expectedProfileID: owner.identity.profileID)
        let target: CoachSeekTarget = sourceLink ? .turn(f.snapshot.coachTurns[0].id) : .day(f.snapshot.days[0].id)
        #expect(routes.queue(target, from: origin, selection: owner, isChangingProfile: false))
        #expect(await coach.seek(try #require(routes.request)))
        let timeline = try #require(coach.timeline)
        #expect(coach.highlightedTurnID == f.snapshot.coachTurns[0].id)
        #expect(timeline.window.viewportAnchor?.rowID == f.snapshot.coachTurns[0].id)
        #expect(timeline.queryError == nil && timeline.error == nil)
        #expect(coach.draft == draft && coach.attachmentDraft.attachments == attachments)
        #expect(try await store.diaryHead(expectedProfileID: owner.identity.profileID) == head)
        let exactRequest: CoachPageRequest = sourceLink ? .aroundTurn(f.snapshot.coachTurns[0].id) : .atDay(f.snapshot.days[0].id)
        #expect(await trace.requests == [.latest, exactRequest])
    }

    @Test func queuedDraftReachesRequest() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        #expect(routes.queue(nil, draft: "For Tuesday, 14 Oct: ", from: origin, selection: owner, isChangingProfile: false))
        #expect(routes.request?.draft == "For Tuesday, 14 Oct: " && routes.request?.target == nil)
    }

    @Test func prefillFillsEmptyDraft() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        #expect(coach.prefill("About the toast in Breakfast: "))
        #expect(coach.draft.text == "About the toast in Breakfast: ")
    }

    @Test func prefillNeverOverwritesUnsentText() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        coach.draft = MealDraft(text: "two eggs")
        #expect(!coach.prefill("For Tuesday, 14 Oct: "))
        #expect(coach.draft.text == "two eggs")
    }

    @Test func seekWaitsForConcurrentInitialReadWithoutLosingRequest() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), gate = Task10Gate(), trace = NavigationPageTrace()
        let store = f.diary.store, targetID = f.snapshot.coachTurns[0].id
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), timelinePageLoading: { request, token in
            await trace.record(request)
            let page = try await store.coachPage(request, expectedSelection: token)
            if request == .latest { await gate.hold(0) }
            return page
        })
        coach.draft = MealDraft(text: "Keep while opening", photos: [Data([4, 5, 6])])
        let draft = coach.draft
        let loading = Task10Fixture.operation(gate: gate) { await coach.loadTimelineIfNeeded() }
        var seeking: Task<Bool, Error>?
        do {
            try await gate.waitForArrivals(1)
            let timeline = try #require(coach.timeline)
            #expect(timeline.exchanges.isEmpty)
            let started = AsyncStream<Void>.makeStream()
            let request = CoachNavigationRequest(identity: owner.identity, target: .turn(targetID), requestID: UUID())
            seeking = Task10Fixture.operation(gate: gate) {
                started.continuation.yield(()); started.continuation.finish()
                return await coach.seek(request)
            }
            for await _ in started.stream { break }
            #expect(await trace.requests == [.latest])
            #expect(timeline.exchanges.isEmpty && timeline.queryError == nil)
            await gate.releaseAll(); _ = try await loading.value
            let seeker = try #require(seeking)
            let applied = try await seeker.value
            #expect(applied && coach.timeline === timeline)
            #expect(timeline.window.viewportAnchor?.rowID == targetID && coach.highlightedTurnID == targetID)
            #expect(timeline.queryError == nil && timeline.error == nil && coach.draft == draft)
            #expect(await trace.requests == [.latest, .aroundTurn(targetID)])
        } catch {
            seeking?.cancel(); loading.cancel(); await gate.releaseAll()
            _ = try? await seeking?.value; _ = try? await loading.value
            throw error
        }
    }

    @Test func oldestDiaryDayAndBackdatedMealOpenExactWindow() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        await coach.loadTimelineIfNeeded()
        let timeline = try #require(coach.timeline)
        let photo = MealPhoto(data: Data([1, 2, 3]), role: .after)
        coach.draft = MealDraft(text: "Keep this draft", photos: [photo.data])
        let draft = coach.draft, head = try await f.diary.store.diaryHead(expectedProfileID: owner.identity.profileID)
        f.metrics.reset()
        #expect(routes.queue(.day(f.snapshot.days[0].id), from: origin, selection: owner, isChangingProfile: false))
        #expect(await coach.seek(try #require(routes.request)))
        #expect(timeline.exchanges.first?.id == f.snapshot.coachTurns[0].id)
        #expect(timeline.window.viewportAnchor?.rowID == f.snapshot.coachTurns[0].id)
        #expect(coach.highlightedTurnID == f.snapshot.coachTurns[0].id)
        #expect(f.metrics.counters.coachPageReads == 1)
        #expect(f.metrics.counters.decodedTurnPayloads <= 20)
        #expect(f.metrics.counters.queryPlans.contains { $0.contains("coach_index_day_sequence") })
        let meal = try await f.diary.store.meal(id: f.snapshot.meals[0].id, expectedProfileID: owner.identity.profileID)
        let source = try #require(meal.sourceTurnID)
        #expect(meal.dayID != f.snapshot.coachTurns[0].activeDayID)
        f.metrics.reset()
        #expect(routes.queue(.turn(source), from: origin, selection: owner, isChangingProfile: false))
        #expect(await coach.seek(try #require(routes.request)))
        #expect(timeline.window.viewportAnchor?.rowID == source)
        #expect(coach.highlightedTurnID == source)
        #expect(timeline.exchanges.contains { $0.id == source })
        #expect(coach.draft == draft)
        #expect(try await f.diary.store.diaryHead(expectedProfileID: owner.identity.profileID) == head)
        #expect(f.metrics.counters.coachPageReads == 1 && f.metrics.counters.decodedTurnPayloads <= 20)
        #expect(f.metrics.counters.completeReads == 0 && f.metrics.counters.completeReconciles == 0)
        #expect(f.metrics.counters.originalPhotoBytes == 0)
        #expect(f.metrics.counters.queryPlans.contains { $0.contains("turnID=?") })
    }

    @Test func missingDayAndLegacyMealHaveHonestEmptyStates() async throws {
        var snapshot = ChatHistoryFixture.pagingSnapshot()
        let empty = TrackingDay(localDate: "2027-01-13", timeZoneID: "UTC", startAt: snapshot.days[0].startAt)
        snapshot.days.append(empty)
        var legacy = snapshot.meals[0]; legacy.id = UUID(); legacy.photos = []; legacy.submissions = []
        snapshot.meals.append(legacy)
        let f = try await NavigationFixture.make(snapshot: snapshot); defer { f.remove() }
        let owner = try #require(f.diary.selection)
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        await coach.loadTimelineIfNeeded()
        let currentIDs = coach.turns.map(\.id), active = f.diary.activeDay?.id
        let noChat = CoachNavigationRequest(identity: owner.identity, target: .day(empty.id), requestID: UUID())
        f.metrics.reset()
        #expect(await coach.seek(noChat) == false)
        #expect(coach.timeline?.queryError == .noChatForDay(empty.id))
        #expect(coach.turns.map(\.id) == currentIDs)
        #expect(f.metrics.counters.coachPageReads == 1 && f.metrics.counters.decodedTurnPayloads == 0)
        let missingSourceID = UUID()
        let missingTurn = CoachNavigationRequest(identity: owner.identity, target: .turn(missingSourceID), requestID: UUID())
        f.metrics.reset()
        #expect(await coach.seek(missingTurn) == false)
        #expect(coach.timeline?.queryError == .missingTurn(missingSourceID))
        #expect(coach.turns.map(\.id) == currentIDs && f.diary.activeDay?.id == active)
        #expect(f.metrics.counters.coachPageReads == 1 && f.metrics.counters.decodedTurnPayloads == 0)
        let meal = try await f.diary.store.meal(id: legacy.id, expectedProfileID: owner.identity.profileID)
        #expect(meal.sourceTurnID == nil)
        await #expect(throws: DiaryError.notFound) { try await f.diary.store.meal(id: UUID(), expectedProfileID: owner.identity.profileID) }
        await #expect(throws: DiaryError.notFound) { try await f.diary.store.diaryDay(id: UUID(), expectedProfileID: owner.identity.profileID) }
    }

    @Test func profileChangedBeforeRouteCannotOpenForeignChat() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        let gate = Task10Gate()
        let history = f.history(routes: routes, origin: origin, held: gate)
        let loading = Task10Fixture.operation(gate: gate) { await history.show() }
        do {
            try await gate.waitForArrivals(1)
            let other = try await f.diary.store.createProfile(DiaryProfile(name: "Other synthetic diary"))
            await f.diary.switchProfile(other.profile.id)
            routes.synchronize(selection: f.diary.selection, isChangingProfile: false)
            await gate.releaseAll(); _ = try await loading.value
            #expect(history.page == nil && history.errorMessage == nil)
            #expect(!routes.queue(.turn(f.snapshot.coachTurns[0].id), from: origin, selection: f.diary.selection, isChangingProfile: false))
            #expect(routes.request == nil && f.diary.selection?.identity.profileID == other.profile.id)
        } catch { await gate.releaseAll(); _ = try? await loading.value; throw error }
    }

    @Test func legacyHistoryRowAndDatePickerOpenFirstTurnWithoutDay() async throws {
        let f = try await NavigationFixture.make(snapshot: ChatHistoryFixture.snapshot()); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        let history = f.history(routes: routes, origin: origin)
        let head = try await f.diary.store.diaryHead(expectedProfileID: owner.identity.profileID)
        f.metrics.reset()
        await history.show()
        let row = try #require(history.page?.segments.first { $0.trackingDayID == nil })
        #expect(history.target(for: row) == .turn(row.firstExchangeID))
        #expect(routes.queue(try #require(history.target(for: row)), from: origin, selection: owner, isChangingProfile: false))
        #expect(routes.request?.target == .turn(f.snapshot.coachTurns[25].id))
        await history.show(row.displayLocalDate)
        let same = try #require(history.page?.segments.first { $0.segmentID == row.segmentID })
        #expect(history.target(for: same) == .turn(row.firstExchangeID))
        #expect(try await f.diary.store.diaryHead(expectedProfileID: owner.identity.profileID) == head)
        #expect(f.metrics.counters.decodedTurnPayloads == 0 && f.metrics.counters.originalPhotoBytes == 0)
    }

    @Test func repeatedDateChoicesRemainDistinct() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        let history = f.history(routes: routes, origin: origin)
        f.metrics.reset()
        await history.show("2027-01-15")
        var rows = try #require(history.page).segments
        #expect(rows.count == 30 && history.page?.hasMore == true)
        #expect(history.page?.cursor?.dateFilterScope == "2027-01-15")
        await history.earlier()
        let last = try #require(history.page)
        rows += last.segments
        #expect(last.segments.count == 20 && !last.hasMore)
        #expect(Set(rows.map(\.segmentID)).count == 50)
        #expect(rows.map(\.firstExchangeID) == stride(from: 98, through: 0, by: -2).map { f.snapshot.coachTurns[$0].id })
        #expect(history.target(for: try #require(last.segments.last)) == .turn(f.snapshot.coachTurns[0].id))
        await history.show("2027-01-14")
        #expect(history.page?.segments.count == 30)
        #expect(history.page?.cursor?.dateFilterScope == "2027-01-14")
        await history.show()
        #expect(history.page?.segments.first?.firstExchangeID == f.snapshot.coachTurns[99].id)
        #expect(history.page?.cursor?.dateFilterScope == nil)
        #expect(f.metrics.counters.decodedTurnPayloads == 0 && f.metrics.counters.completeReads == 0)
        #expect(f.metrics.counters.queryPlans.contains { $0.contains("coach_segment_date_last") })
        #expect(f.metrics.counters.queryPlans.contains { $0.contains("coach_segment_last") })
    }

    @Test func restoredTimelineRejectsQueuedNavigation() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        #expect(routes.queue(.turn(f.snapshot.coachTurns[0].id), from: origin, selection: owner, isChangingProfile: false))
        let oldRequest = try #require(routes.request), gate = Task10Gate()
        let history = f.history(routes: routes, origin: origin, held: gate)
        let loading = Task10Fixture.operation(gate: gate) { await history.show() }
        do {
            try await gate.waitForArrivals(1)
            try await f.diary.store.restore(f.snapshot, expectedProfileID: owner.identity.profileID)
            await f.diary.switchProfile(owner.identity.profileID)
            routes.synchronize(selection: f.diary.selection, isChangingProfile: false)
            await gate.releaseAll(); _ = try await loading.value
            #expect(history.page == nil && history.errorMessage == nil && routes.request == nil)
            #expect(f.diary.selection?.identity != oldRequest.identity)
            #expect(!routes.queue(oldRequest.target, from: origin, selection: f.diary.selection, isChangingProfile: false))
            let fresh = try #require(routes.origin(selection: f.diary.selection, isChangingProfile: false))
            #expect(routes.queue(oldRequest.target, from: fresh, selection: f.diary.selection, isChangingProfile: false))
            #expect(routes.request?.identity == f.diary.selection?.identity)
        } catch { await gate.releaseAll(); _ = try? await loading.value; throw error }
    }

    @Test(arguments: [false, true])
    func profileRoundTripRejectsOldSelectionResponse(failedTransition: Bool) async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false)), gate = Task10Gate()
        let history = f.history(routes: routes, origin: origin, held: gate)
        let loading = Task10Fixture.operation(gate: gate) { await history.show("2027-01-15") }
        do {
            try await gate.waitForArrivals(1)
            routes.synchronize(selection: owner, isChangingProfile: true)
            if !failedTransition {
                let other = try await f.diary.store.createProfile(DiaryProfile(name: "Round trip synthetic"))
                await f.diary.switchProfile(other.profile.id)
                routes.synchronize(selection: f.diary.selection, isChangingProfile: false)
                await f.diary.switchProfile(owner.identity.profileID)
            }
            routes.synchronize(selection: f.diary.selection, isChangingProfile: false)
            await gate.releaseAll(); _ = try await loading.value
            #expect(f.diary.selection?.identity == owner.identity)
            #expect(history.page == nil && history.errorMessage == nil)
            #expect(!routes.queue(.turn(f.snapshot.coachTurns[0].id), from: origin, selection: f.diary.selection, isChangingProfile: false))
            #expect(routes.request == nil)
        } catch { await gate.releaseAll(); _ = try? await loading.value; throw error }
    }

    @Test(arguments: [false, true])
    func consumingOldRequestDoesNotClearNewRequest(oldLoadFails: Bool) async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false)), gate = Task10Gate()
        let history = f.history(routes: routes, origin: origin, held: gate, failHeld: oldLoadFails, holdDate: "2027-01-15")
        routes.queue(.turn(f.snapshot.coachTurns[0].id), from: origin, selection: owner, isChangingProfile: false)
        let oldID = try #require(routes.request?.requestID)
        let loading = Task10Fixture.operation(gate: gate) { await history.show("2027-01-15"); routes.consume(oldID) }
        do {
            try await gate.waitForArrivals(1)
            routes.queue(.turn(f.snapshot.coachTurns[1].id), from: origin, selection: owner, isChangingProfile: false)
            let newer = try #require(routes.request)
            await history.show("2027-01-14")
            let current = history.page
            await gate.releaseAll(); _ = try await loading.value
            #expect(history.page == current && history.errorMessage == nil && !history.isLoading)
            #expect(routes.request == newer)
            routes.consume(oldID); #expect(routes.request == newer)
            routes.consume(newer.requestID); #expect(routes.request == nil)
        } catch { await gate.releaseAll(); _ = try? await loading.value; throw error }
    }

    @Test(arguments: ["roundTrip", "restore", "cancel"], [false, true])
    func suspendedConsumerCannotPublishStaleSuccessErrorOrCleanup(change: String, sourceFails: Bool) async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = f.routes(), gate = Task10Gate()
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        let store = f.diary.store, oldTurn = f.snapshot.coachTurns[0].id
        let freshGate = Task10Gate(), trace = NavigationPageTrace()
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), timelinePageLoading: { request, token in
            await trace.record(request)
            let result = try await store.coachPage(request, expectedSelection: token)
            if request == .aroundTurn(oldTurn) {
                await gate.hold(0)
                if sourceFails { throw DiaryError.persistenceFailed }
            } else if request == .latest, token != owner {
                await freshGate.hold(0)
            }
            return result
        })
        await coach.loadTimelineIfNeeded()
        let previous = try #require(coach.timeline), originalIDs = previous.exchanges.map(\.id)
        routes.queue(.turn(oldTurn), from: origin, selection: owner, isChangingProfile: false)
        let first = try #require(routes.request)
        let consuming = Task10Fixture.operation(gate: gate) {
            let applied = await coach.seek(first)
            routes.consume(first.requestID)
            return applied
        }
        var freshLoading: Task<Void, Error>?
        do {
            try await gate.waitForArrivals(1)
            if change == "restore" {
                try await store.restore(f.snapshot, expectedProfileID: owner.identity.profileID)
                await f.diary.switchProfile(owner.identity.profileID)
            } else if change == "roundTrip" {
                let other = try await store.createProfile(DiaryProfile(name: "Consumer round trip"))
                await f.diary.switchProfile(other.profile.id)
                await f.diary.switchProfile(owner.identity.profileID)
            } else { consuming.cancel() }
            routes.synchronize(selection: f.diary.selection, isChangingProfile: false)
            let currentOrigin = try #require(routes.origin(selection: f.diary.selection, isChangingProfile: false))
            routes.queue(.turn(f.snapshot.coachTurns[99].id), from: currentOrigin,
                         selection: f.diary.selection, isChangingProfile: false)
            let newer = try #require(routes.request)
            if change != "cancel" {
                let started = AsyncStream<Void>.makeStream()
                freshLoading = Task10Fixture.operation(gate: freshGate) {
                    started.continuation.yield(()); started.continuation.finish()
                    await coach.loadTimelineIfNeeded()
                }
                for await _ in started.stream { break }
                #expect(coach.timeline === previous)
                #expect(previous.window.identity == f.diary.selection?.identity)
                #expect(previous.window.reservedCapacity >= 20)
                #expect(previous.exchanges.isEmpty)
                #expect(await trace.requests == [.latest, .aroundTurn(oldTurn)])
                #expect(routes.request == newer)
                await gate.releaseAll()
                try await freshGate.waitForArrivals(1)
                // The old success/error has drained; the fresh page still cannot publish.
                #expect(previous.exchanges.isEmpty && previous.requestedRanges.isEmpty)
                #expect(previous.error == nil && previous.queryError == nil && coach.errorMessage == nil)
                #expect(routes.request == newer)
                #expect(await trace.requests == [.latest, .aroundTurn(oldTurn), .latest])
                await freshGate.releaseAll()
                _ = try await freshLoading?.value
            } else { await gate.releaseAll() }
            #expect(try await consuming.value == false)
            #expect(routes.request == newer)
            let current = try #require(coach.timeline)
            #expect(current === previous && current.exchanges.map(\.id) == originalIDs && current.error == nil)
            #expect(current.queryError == nil)
            #expect(coach.errorMessage == nil)
        } catch {
            consuming.cancel(); freshLoading?.cancel()
            await gate.releaseAll(); await freshGate.releaseAll()
            _ = try? await consuming.value; _ = try? await freshLoading?.value
            throw error
        }
    }
    private func waitForReconnectEvidence(_ message: String, _ condition: () -> Bool) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock().now.advanced(by: .seconds(10))
        while !condition() {
            guard clock.now < deadline else {
                Issue.record(Comment(rawValue: message))
                throw DiaryError.persistenceFailed
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test(arguments: [false, true])
    func reconnectCatchesExternalTailWithoutAnotherInitialLoad(initiallyEmpty: Bool) async throws {
        let f = try await NavigationFixture.make(snapshot: ChatHistoryFixture.pagingSnapshot(exchanges: initiallyEmpty ? 0 : 100))
        defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        var connection: Task<Void, Never>? = Task { await coach.connectTimeline() }
        do {
            try await waitForReconnectEvidence("Initial Coach timeline did not load") { coach.timeline?.window.identity != nil }
            connection?.cancel(); await connection?.value
            let timeline = try #require(coach.timeline), owner = try #require(f.diary.selection)
            let preparation = try await f.diary.store.coachCapturePreparation(at: f.snapshot.days[0].startAt,
                expectedProfileID: owner.identity.profileID)
            let id = UUID()
            let payload = try CoachSubmissionPayload(submissionID: id, text: "Captured from Today while Coach is absent",
                attachments: [], context: preparation.context)
            _ = try await f.diary.store.captureCoachSubmission(payload, expectedSelection: owner,
                expectedProfileID: owner.identity.profileID)
            try await f.diary.store.completeCoachTurn(turnID: id, assistantText: "External capture completed",
                expectedProfileID: owner.identity.profileID)
            #expect(!timeline.exchanges.contains { $0.id == id })
            f.metrics.reset()
            connection = Task { await coach.connectTimeline() }
            try await waitForReconnectEvidence("Reconnected Coach missed the offscreen external capture") {
                timeline.exchanges.contains { $0.id == id && $0.assistantText == "External capture completed" } && timeline.refreshTask == nil
            }
            #expect(coach.timeline === timeline)
            #expect(timeline.window.viewport == .latest)
            #expect(timeline.window.pages.last?.hasLater == false)
            #expect(f.metrics.counters.coachPageReads == 1)
            #expect(f.metrics.counters.decodedTurnPayloads <= 40)
            #expect(f.metrics.counters.completeReads == 0)
            #expect(timeline.window.residentCount <= 20 && timeline.window.reservedCapacity == 0)
            connection?.cancel(); await connection?.value
        } catch {
            connection?.cancel(); await connection?.value
            throw error
        }
    }

    @Test func reconnectRefreshesMissedResidentReplyAndPreservesHistory() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        var connection: Task<Void, Never>? = Task { await coach.connectTimeline() }
        do {
            try await waitForReconnectEvidence("Initial Coach timeline did not load") { coach.timeline?.window.identity != nil }
            connection?.cancel(); await connection?.value
            let timeline = try #require(coach.timeline), owner = try #require(f.diary.selection)
            await timeline.seek(.turn(f.snapshot.coachTurns[40].id))
            let id = try #require(timeline.exchanges.dropFirst(5).first?.id)
            let anchor = CoachViewportAnchor(rowID: id, offset: -11.5, focusedExchangeID: id)
            timeline.setViewport(.history(anchor), visibleIDs: [id], measuredAnchor: anchor)
            let beforeIDs = timeline.exchanges.map(\.id)
            try await f.diary.store.completeCoachTurn(turnID: id, assistantText: "Completed while Coach was absent",
                expectedProfileID: owner.identity.profileID)
            let preparation = try await f.diary.store.coachCapturePreparation(at: f.snapshot.days[0].startAt,
                expectedProfileID: owner.identity.profileID)
            let external = UUID()
            let payload = try CoachSubmissionPayload(submissionID: external, text: "New external tail",
                attachments: [], context: preparation.context)
            _ = try await f.diary.store.captureCoachSubmission(payload, expectedSelection: owner,
                expectedProfileID: owner.identity.profileID)
            f.metrics.reset()
            connection = Task { await coach.connectTimeline() }
            try await waitForReconnectEvidence("Reconnected Coach missed a resident completion") {
                timeline.exchanges.first { $0.id == id }?.assistantText == "Completed while Coach was absent" && timeline.refreshTask == nil
            }
            #expect(coach.timeline === timeline)
            #expect(timeline.exchanges.map(\.id) == beforeIDs)
            #expect(!timeline.exchanges.contains { $0.id == external })
            #expect(timeline.window.viewport == .history(anchor))
            #expect(timeline.restoration == .preserve(anchor))
            #expect(timeline.window.pages.last?.hasLater == true)
            #expect(f.metrics.counters.coachPageReads == 0)
            #expect(f.metrics.counters.decodedTurnPayloads <= 20)
            #expect(f.metrics.counters.completeReads == 0)
            connection?.cancel(); await connection?.value
        } catch {
            connection?.cancel(); await connection?.value
            throw error
        }
    }

    @Test func unchangedReconnectRefreshesOnlyBoundedResidents() async throws {
        let f = try await NavigationFixture.make(); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        var connection: Task<Void, Never>? = Task { await coach.connectTimeline() }
        do {
            try await waitForReconnectEvidence("Initial Coach timeline did not load") { coach.timeline?.window.identity != nil }
            connection?.cancel(); await connection?.value
            let timeline = try #require(coach.timeline), revision = timeline.revision, before = timeline.exchanges
            f.metrics.reset()
            connection = Task { await coach.connectTimeline() }
            try await waitForReconnectEvidence("Reconnected Coach did not reconcile bounded residents") {
                timeline.revision > revision && timeline.refreshTask == nil
            }
            #expect(coach.timeline === timeline && timeline.exchanges == before)
            #expect(f.metrics.counters.coachPageReads == 0)
            #expect(f.metrics.counters.decodedTurnPayloads <= before.count)
            #expect(f.metrics.counters.completeReads == 0)
            #expect(timeline.window.reservedCapacity == 0)
            connection?.cancel(); await connection?.value
        } catch {
            connection?.cancel(); await connection?.value
            throw error
        }
    }


}

private actor NavigationPageTrace {
    private(set) var requests: [CoachPageRequest] = []
    func record(_ request: CoachPageRequest) { requests.append(request) }
}

@MainActor private struct NavigationFixture {
    let files: CaptureFixture
    let diary: DiaryViewModel
    let metrics: DiaryQueryDiagnostics
    var snapshot: DiarySnapshot { files.before }
    func remove() { diary.enterBackground(); files.remove() }
    static func make(snapshot: DiarySnapshot = ChatHistoryFixture.pagingSnapshot()) async throws -> Self {
        let files = try CaptureFixture(snapshot: snapshot), metrics = DiaryQueryDiagnostics()
        let store = DiaryStore(directory: files.root, diagnostics: metrics)
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        _ = try #require(diary.selection)
        return Self(files: files, diary: diary, metrics: metrics)
    }
    func routes() -> CoachNavigationOwner {
        let routes = CoachNavigationOwner()
        routes.synchronize(selection: diary.selection, isChangingProfile: diary.isChangingProfile)
        return routes
    }
    func history(routes: CoachNavigationOwner, origin: CoachNavigationOrigin, held gate: Task10Gate? = nil,
                 failHeld: Bool = false, holdDate: String? = nil) -> CoachHistoryModel {
        CoachHistoryModel(origin: origin, isCurrent: {
            routes.isCurrent(origin, selection: diary.selection, isChangingProfile: diary.isChangingProfile)
        }, load: { date, cursor, token in
            let page: CoachDayPage
            if let date {
                page = try await diary.store.coachSegments(displayLocalDate: date, before: cursor,
                    expectedSelection: token, expectedProfileID: token.identity.profileID)
            } else {
                page = try await diary.store.coachDays(before: cursor, expectedSelection: token,
                    expectedProfileID: token.identity.profileID)
            }
            if let gate, holdDate == nil || date == holdDate {
                await gate.hold(0)
                if failHeld { throw DiaryError.persistenceFailed }
            }
            return page
        })
    }
}
