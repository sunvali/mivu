import CoreGraphics
import Foundation
import Testing
@testable import Mivu

/// Pip's gesture library and moment table as shared data for other ports; set MIVU_WRITE_FIXTURES=1 to regenerate.
struct PipGestureFixtureTests {
    private static let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/pip/gestures.json")

    /// Every `PipMoment` value: each hour, each tap level up to the wrap, and every other case once.
    static let moments: [(String, PipMoment)] =
        (0...23).map { ("greeting:\($0)", .greeting(hour: $0)) }
        + (0...4).map { ("tapped:\($0)", .tapped(level: $0)) }
        + (0...5).map { ("progressTap:\($0)", .progressTap(level: $0)) }
        + [true, false].flatMap { [("presenting:\($0)", .presenting(cheer: $0)), ("progressEntrance:\($0)", .progressEntrance(cheer: $0))] }
        + [("welcomeBack", .welcomeBack), ("attentive", .attentive), ("submitted", .submitted), ("thinking", .thinking),
           ("saved", .saved), ("reviewed", .reviewed), ("recovery", .recovery), ("firstMealToday", .firstMealToday),
           ("dayComplete", .dayComplete), ("curious", .curious), ("patted", .patted), ("earTwitch", .earTwitch),
           ("progressRange", .progressRange)]

    private static func pose(_ pose: PipPose) -> [String: Any] {
        [
            "joints": pose.joints.mapValues { joint -> [String: Any] in
                ["rotation": Double(joint.rotation), "offset": [Double(joint.offset.x), Double(joint.offset.y)],
                 "scale": [Double(joint.scale.width), Double(joint.scale.height)]]
            },
            "eyes": pose.eyes.rawValue, "mouth": pose.mouth.rawValue, "gaze": [Double(pose.gaze.x), Double(pose.gaze.y)],
            "blush": pose.blush, "hearts": pose.hearts, "set": pose.set.rawValue, "headTurn": Double(pose.headTurn),
        ]
    }

    static func fixture() throws -> Data {
        let gestures = PipGestureLibrary.all.map { gesture -> [String: Any] in
            var entry: [String: Any] = [
                "name": gesture.name, "loops": gesture.loops,
                "keys": gesture.keys.map { ["at": $0.at, "pose": pose($0.pose)] as [String: Any] },
            ]
            if let end = gesture.endSet { entry["endSet"] = end.rawValue }
            return entry
        }
        let object: [String: Any] = [
            "generatedBy": "ios/MivuTests/PipGestureFixtureTests.swift",
            "gestures": gestures,
            "moments": Dictionary(uniqueKeysWithValues: moments.map { ($0.0, PipGestureLibrary.gesture(for: $0.1).name) }),
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
            + Data("\n".utf8)
    }

    @Test func fixtureMatchesCurrentLibrary() throws {
        let data = try Self.fixture()
        if ProcessInfo.processInfo.environment["MIVU_WRITE_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: Self.file)
        }
        #expect(try Data(contentsOf: Self.file) == data, "gestures.json is stale")
    }
}
