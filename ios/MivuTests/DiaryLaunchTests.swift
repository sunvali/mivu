import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct DiaryLaunchTests {
    @Test(arguments: [
        (["Mivu"], ["XCTestConfigurationFilePath": "/tmp/synthetic-test-configuration"], false),
        (["Mivu", "--diary-ui-test", "00000000-0000-4000-8000-000000000001"], ["XCTestConfigurationFilePath": "/tmp/synthetic-test-configuration"], true),
        (["Mivu"], [:], true),
        (["Mivu", "--diary-ui-test", "invalid"], ["XCTestConfigurationFilePath": "/tmp/synthetic-test-configuration"], false)
    ])
    func unitHostDoesNotConstructOwnerDiary(arguments: [String], environment: [String: String], expected: Bool) {
        #expect(DiaryLaunch.shouldLaunchDiary(arguments: arguments, environment: environment) == expected)
    }
}
