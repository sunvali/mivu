import XCTest

extension XCUIApplication {
    var diaryPills: XCUIElementQuery { buttons.matching(identifier: "diaryDayPill") }
    var selectedDiaryDate: String? { diaryPills.matching(NSPredicate(format: "selected == true")).firstMatch.value as? String }

    /// Swipes the Diary week strip toward `date` (`yyyy-MM-dd`) and taps its day.
    @discardableResult func selectDiaryDate(_ date: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let strip = descendants(matching: .any)["diaryWeekStrip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 10), file: file, line: line)
        let pill = diaryPills.matching(NSPredicate(format: "value == %@", date)).firstMatch
        for _ in 0..<40 where !(pill.exists && pill.isHittable) {
            if (selectedDiaryDate ?? "") > date { strip.swipeRight() } else { strip.swipeLeft() }
        }
        guard pill.exists && pill.isHittable else { XCTFail("No Diary day \(date)", file: file, line: line); return false }
        pill.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: pill)
        return XCTWaiter.wait(for: [selected], timeout: 5) == .completed
    }

    static func diaryLabel(_ date: Date, zone: String = "UTC") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: zone); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
