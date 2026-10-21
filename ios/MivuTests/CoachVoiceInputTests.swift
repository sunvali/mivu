import AVFoundation
import Testing
@testable import Mivu

@Suite struct CoachVoiceInputTests {
    @Test func levelMapsSilenceToZeroAndLoudSpeechNearOne() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        func buffer(amplitude: Float) throws -> AVAudioPCMBuffer {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
            buffer.frameLength = 480
            for i in 0..<480 { buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.2) }
            return buffer
        }
        #expect(CoachVoiceInput.level(of: try buffer(amplitude: 0)) == 0)
        #expect(CoachVoiceInput.level(of: try buffer(amplitude: 0.001)) < 0.1)
        #expect(CoachVoiceInput.level(of: try buffer(amplitude: 1)) > 0.9)
        #expect(CoachVoiceInput.level(of: try buffer(amplitude: 0.05)) > CoachVoiceInput.level(of: try buffer(amplitude: 0.01)))
    }


    @Test func spokenTextAppendsAfterTypedDraft() {
        #expect(CoachVoiceInput.merged(draft: "", spoken: " two eggs ") == "two eggs")
        #expect(CoachVoiceInput.merged(draft: "lunch:", spoken: "two eggs") == "lunch: two eggs")
        #expect(CoachVoiceInput.merged(draft: "lunch: ", spoken: "two eggs") == "lunch: two eggs")
        #expect(CoachVoiceInput.merged(draft: "lunch:", spoken: "  ") == "lunch:")
    }
}
