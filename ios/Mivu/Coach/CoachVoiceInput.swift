import AVFoundation
import Speech
import SwiftUI

/// Fills the Coach draft from on-device speech. Audio is never stored or sent; only text the user sends leaves the draft.
@Observable @MainActor final class CoachVoiceInput {
    enum Phase { case idle, preparing, listening }
    private(set) var phase = Phase.idle
    private(set) var note: String?
    /// Recent microphone levels, oldest first, each 0...1, for the live waveform.
    private(set) var levels = [Float](repeating: 0, count: CoachVoiceInput.waveformBars)
    nonisolated static let waveformBars = 3
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?

    nonisolated static func merged(draft: String, spoken: String) -> String {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return draft }
        guard !draft.isEmpty else { return spoken }
        return draft.last!.isWhitespace ? draft + spoken : draft + " " + spoken
    }

    /// Speech loudness of one buffer, mapped from -50...0 dBFS to 0...1.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        guard rms > 0 else { return 0 }
        return min(max((20 * log10(rms) + 50) / 50, 0), 1)
    }

    /// Streams the transcript appended to `draft` into `update` until `stop()`.
    func start(appendingTo draft: String, update: @escaping @MainActor (String) -> Void) async {
        guard phase == .idle else { return }
        phase = .preparing; note = nil
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                throw Failure("Allow microphone access in Settings to log by voice.")
            }
            guard await Self.speechAuthorized() else { throw Failure("Allow speech recognition in Settings to log by voice.") }
            let english = Locale(identifier: "en-US")
            let transcriber: any SpeechModule
            let transcripts: AsyncThrowingStream<(text: String, isFinal: Bool), any Error>
            if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: english) {
                let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                (transcriber, transcripts) = (module, Self.texts(module.results) { (String($0.text.characters), $0.isFinal) })
            } else if let locale = await DictationTranscriber.supportedLocale(equivalentTo: english) {
                // Devices without the newer model (and the Simulator) still have dictation.
                let module = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
                (transcriber, transcripts) = (module, Self.texts(module.results) { (String($0.text.characters), $0.isFinal) })
            } else {
                throw Failure("Voice input isn’t available on this iPhone. Type, or use the keyboard microphone.")
            }
            if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                note = "Preparing voice…"
                try await download.downloadAndInstall()
                note = nil
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw Failure("Voice input isn’t available on this iPhone. Type, or use the keyboard microphone.")
            }
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let engine = AVAudioEngine()
            try Self.tap(engine.inputNode, into: continuation, as: format) { [weak self] level in
                Task { @MainActor in self?.levels = (self?.levels.dropFirst() ?? []) + [level] }
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.start(inputSequence: stream)
            guard phase == .preparing else { // stopped while preparing
                engine.inputNode.removeTap(onBus: 0); continuation.finish(); await analyzer.cancelAndFinishNow(); return
            }
            // No suspension from here on, so stop() always sees what it must release.
            (self.engine, self.analyzer, self.input) = (engine, analyzer, continuation)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            results = Task {
                var finished = ""
                do {
                    for try await (text, isFinal) in transcripts {
                        if isFinal { finished += text }
                        update(Self.merged(draft: draft, spoken: isFinal ? finished : finished + text))
                    }
                } catch { self.note = "Voice input stopped. Your text is kept." }
            }
            phase = .listening
            AccessibilityNotification.Announcement("Listening").post()
        } catch {
            note = (error as? Failure)?.message ?? "Voice input couldn’t start. Type, or use the keyboard microphone."
            await stop()
        }
    }

    /// Finishes the last words into the draft, then releases the microphone.
    func stop() async {
        guard phase != .idle else { return }
        let wasListening = phase == .listening
        phase = .idle
        engine?.inputNode.removeTap(onBus: 0); engine?.stop()
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        (engine, analyzer, input, results) = (nil, nil, nil, nil)
        levels = [Float](repeating: 0, count: Self.waveformBars)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if wasListening { AccessibilityNotification.Announcement("Stopped listening").post() }
    }

    private struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }

    private nonisolated static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { done in SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) } }
    }

    /// Gives both transcriber kinds one result shape.
    private nonisolated static func texts<Results: AsyncSequence & Sendable>(
        _ results: Results, _ read: @escaping @Sendable (Results.Element) -> (String, Bool)
    ) -> AsyncThrowingStream<(text: String, isFinal: Bool), any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do { for try await result in results { output.yield(read(result)) }; output.finish() }
                catch { output.finish(throwing: error) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs on the audio thread, so it must stay outside the main actor.
    private nonisolated static func tap(_ node: AVAudioInputNode, into input: AsyncStream<AnalyzerInput>.Continuation,
                                        as format: AVAudioFormat, level: @escaping @Sendable (Float) -> Void) throws {
        let source = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: source, to: format) else {
            throw Failure("Voice input isn’t available on this iPhone. Type, or use the keyboard microphone.")
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            level(Self.level(of: buffer))
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / source.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var supplied = false
            converter.convert(to: converted, error: nil) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            input.yield(AnalyzerInput(buffer: converted))
        }
    }
}
