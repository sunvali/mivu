import XCTest
@testable import Mivu

final class ReportReplyTests: XCTestCase {
    func testReportEmailQuotesTheReplyForSupport() throws {
        let url = MivuLinks.reportReply("Eat 500 kcal & skip lunch?")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "support@mivuapp.com")
        let items: [String: String] = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { item in (item.name, item.value ?? "") })
        XCTAssertEqual(items["subject"], "Report a Coach reply")
        XCTAssertTrue(try XCTUnwrap(items["body"]).contains("Eat 500 kcal & skip lunch?"))
    }
}
