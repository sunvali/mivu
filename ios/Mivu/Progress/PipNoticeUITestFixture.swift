#if DEBUG
import Foundation

/// UI tests pin what Pip noticed today instead of seeding weeks of synthetic history; the rules have their own unit tests.
enum PipNoticeUITestFixture {
    static var notice: PipNotice? {
        DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--pip-notice-fixture") ? .proteinShort(short: 9, days: 12) : nil
    }
}
#endif
