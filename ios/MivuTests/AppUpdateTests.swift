import Foundation
import Testing
@testable import Mivu

/// Answers by host: the App Store lookup and the website config. Synthetic only.
private final class UpdateStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var replies: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var offline = false

    static func session(store: (Int, String)? = nil, config: (Int, String)? = nil, offline: Bool = false) -> URLSession {
        replies = [:]
        replies["itunes.apple.com"] = store
        replies["mivuapp.com"] = config
        self.offline = offline
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [UpdateStub.self]
        return URLSession(configuration: settings)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard !Self.offline, let (status, body) = Self.replies[request.url?.host ?? ""] else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let reply = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor @Suite(.serialized) struct AppUpdateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "AppUpdateTests-" + UUID().uuidString)! }
    private func store(_ version: String, daysAgo: Double) -> (Int, String) {
        let date = ISO8601DateFormatter().string(from: now.addingTimeInterval(-daysAgo * 86_400))
        return (200, #"{"resultCount":1,"results":[{"version":"\#(version)","currentVersionReleaseDate":"\#(date)"}]}"#)
    }
    private func update(_ version: String = "1.8.0", defaults: UserDefaults? = nil, session: URLSession) -> AppUpdate {
        AppUpdate(defaults: defaults ?? self.defaults(), version: version, session: session)
    }

    @Test func newerStoreVersionAfterSevenDaysIsAvailable() async {
        let ready = update(session: UpdateStub.session(store: store("1.9.0", daysAgo: 8)))
        await ready.check(now: now)
        #expect(ready.available == "1.9.0")
        let phasing = update(session: UpdateStub.session(store: store("1.9.0", daysAgo: 6)))
        await phasing.check(now: now)
        #expect(phasing.available == nil)
    }

    @Test func olderStoreVersionShowsNothing() async {
        let app = update("2.0.0", session: UpdateStub.session(store: store("1.9.0", daysAgo: 30)))
        await app.check(now: now)
        #expect(app.available == nil)
        #expect(!app.showsCard(now: now))
    }

    @Test func malformedLookupShowsNothing() async {
        for body in ["<html>login</html>", #"{"resultCount":0,"results":[]}"#] {
            let app = update(session: UpdateStub.session(store: (200, body)))
            await app.check(now: now)
            #expect(app.available == nil)
        }
    }

    @Test func numericCompare() async {
        let app = update("1.9.0", session: UpdateStub.session(store: store("1.10.0", daysAgo: 8)))
        await app.check(now: now)
        #expect(app.available == "1.10.0")
    }

    @Test func cardReturnsOnceAWeekAfterDismiss() async {
        let app = update(session: UpdateStub.session(store: store("1.9.0", daysAgo: 8)))
        await app.check(now: now)
        #expect(app.showsCard(now: now))
        app.dismissCard(now: now)
        #expect(!app.showsCard(now: now.addingTimeInterval(6 * 86_400)))
        #expect(app.showsCard(now: now.addingTimeInterval(7 * 86_400)))
        app.dismissCard(now: now.addingTimeInterval(7 * 86_400))
        #expect(!app.showsCard(now: now.addingTimeInterval(60 * 86_400)))
    }

    @Test func newVersionResetsCard() async {
        let saved = defaults()
        let first = update(defaults: saved, session: UpdateStub.session(store: store("1.9.0", daysAgo: 8)))
        await first.check(now: now)
        first.dismissCard(now: now); first.dismissCard(now: now)
        let next = update(defaults: saved, session: UpdateStub.session(store: store("1.10.0", daysAgo: 8)))
        await next.check(now: now)
        #expect(next.showsCard(now: now))
    }

    @Test func minimumAboveVersionBlocks() async {
        let app = update(session: UpdateStub.session(config: (200, #"{"ios":"1.8.1","android":"1.0.0"}"#)))
        #expect(!app.isBlocked)
        await app.check(now: now)
        #expect(app.isBlocked)
    }

    @Test func configFailureKeepsLastMinimum() async {
        let saved = defaults()
        await update(defaults: saved, session: UpdateStub.session(config: (200, #"{"ios":"1.9.0"}"#))).check(now: now)
        for session in [UpdateStub.session(config: (404, "Not found")), UpdateStub.session(config: (200, "<html>login</html>")),
                        UpdateStub.session(offline: true)] {
            let app = update(defaults: saved, session: session)
            await app.check(now: now)
            #expect(app.isBlocked)
        }
    }

    @Test func lowerMinimumUnblocks() async {
        let saved = defaults()
        await update(defaults: saved, session: UpdateStub.session(config: (200, #"{"ios":"1.9.0"}"#))).check(now: now)
        let app = update(defaults: saved, session: UpdateStub.session(config: (200, #"{"ios":"1.0.0"}"#)))
        #expect(app.isBlocked)
        await app.check(now: now)
        #expect(!app.isBlocked)
    }

    @Test func checksAtMostOnceAnHour() async {
        let app = update(session: UpdateStub.session(config: (200, #"{"ios":"1.0.0"}"#)))
        await app.check(now: now)
        UpdateStub.replies["mivuapp.com"] = (200, #"{"ios":"9.0.0"}"#)
        await app.check(now: now.addingTimeInterval(30 * 60))
        #expect(!app.isBlocked)
        await app.check(now: now.addingTimeInterval(61 * 60))
        #expect(app.isBlocked)
    }

    @Test func firstRunRecordsWithoutShowing() {
        let saved = defaults()
        let fresh = WhatsNew(defaults: saved, version: "1.9.0", notes: ["1.9.0": ["Synthetic highlight"]])
        fresh.recordLaunch()
        #expect(fresh.pending == nil)
    }

    @Test func updateWithNotesShowsOnceUntilSeen() {
        let saved = defaults()
        WhatsNew(defaults: saved, version: "1.8.0", notes: [:]).recordLaunch()
        let updated = WhatsNew(defaults: saved, version: "1.9.0", notes: ["1.9.0": ["Synthetic highlight"]])
        updated.recordLaunch()
        #expect(updated.pending?.count == 1)
        updated.recordLaunch() // a second launch of the same version keeps it until seen
        #expect(updated.pending?.count == 1)
        updated.markSeen()
        #expect(updated.pending == nil)
    }

    @Test func updateWithoutNotesShowsNothing() {
        let saved = defaults()
        WhatsNew(defaults: saved, version: "1.8.0", notes: [:]).recordLaunch()
        let fix = WhatsNew(defaults: saved, version: "1.8.1", notes: ["1.9.0": ["Synthetic highlight"]])
        fix.recordLaunch()
        #expect(fix.pending == nil)
    }
}
