import CoreGraphics
import Foundation
import Testing
@testable import Mivu

@Suite struct PipRigAssetTests {
    static func bundledData() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "Characters/pip/pip-rig.json", withExtension: nil))
        return try Data(contentsOf: url)
    }

    @Test func bundledRigLoadsAndHasHeadParts() throws {
        let asset = try PipRigAsset.load(Self.bundledData())
        #expect(asset.version == 2)
        #expect(asset.parts.contains { $0.id.hasPrefix("pupil-l") })
        #expect(asset.frames["today"].map { CGRect(x: 0, y: 0, width: 512, height: 512).intersects($0) } == true)
        // Coach is a bust peeking over the composer: the crop ends on the bar line where the seated paws rest.
        #expect(asset.frames["coach"].map { abs($0.maxY - 383) < 0.5 && $0.height < 380 } == true)
    }

    @Test func rejectsOversizeWrongVersionAndBadPath() throws {
        #expect(throws: PipRigAsset.Error.tooLarge) { try PipRigAsset.load(Data(count: 1_048_577)) }
        let json = try #require(String(data: Self.bundledData(), encoding: .utf8))
        let v1 = Data(json.replacingOccurrences(of: "\"version\":2", with: "\"version\":1").utf8)
        #expect(throws: PipRigAsset.Error.version) { try PipRigAsset.load(v1) }
        #expect(throws: PipRigAsset.Error.badPath("M 0 0 A 1 1")) { try PipRigAsset.cgPath("M 0 0 A 1 1") }
    }

    @Test func cgPathParsesCubicAndQuadratic() throws {
        let box = try PipRigAsset.cgPath("M0 0 C 10 0 10 10 0 10 Q 5 5 0 0 Z").boundingBoxOfPath
        #expect(abs(box.width - 7.5) < 0.5 && abs(box.height - 10) < 0.5 && abs(box.minX) < 0.5)
    }
}
