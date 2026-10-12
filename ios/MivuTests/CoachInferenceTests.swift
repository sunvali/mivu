import Foundation
import Testing
@testable import Mivu

struct CoachInferenceTests {
    @Test func validatesPNGAndJPEGSignaturesAndSize() throws {
        #expect(try CoachInferenceInput.imageMIME(SyntheticConnectionProbe.image) == "image/png")
        #expect(try CoachInferenceInput.imageMIME(Data([255, 216, 255, 224])) == "image/jpeg")
        for data in [Data(), Data([255, 216]), Data("image/png".utf8), Data([137, 80, 78, 71]), SyntheticConnectionProbe.image + Data(repeating: 0, count: 5_242_880)] {
            #expect(throws: ResponsesClient.Failure.invalidInput) { try CoachInferenceInput.imageMIME(data) }
        }
    }

    @Test func boundsContinuationAndFunctionOutputs() throws {
        #expect(throws: ResponsesClient.Failure.invalidInput) {
            try CoachInferenceInput.functionOutput(callID: "synthetic", output: String(repeating: "x", count: 65_537)).object()
        }
        #expect(throws: ResponsesClient.Failure.invalidInput) {
            try CoachInferenceInput.priorOutput(Data(repeating: 32, count: 1_048_577)).object()
        }
    }
}
