@preconcurrency import AVFoundation
import Foundation
import Speech

// MARK: - Speech Transcriber Bridge (macOS 26 SpeechAnalyzer)
//
// macOS 26 replaced the old SFSpeechRecognizer pipeline with SpeechAnalyzer:
// fully on-device, materially lower latency, and no network round trip. This
// wraps it behind a tiny interface so VoiceConversationService can use it when
// the OS supports it and fall back to SFSpeechRecognizer when it doesn't.
//
// Turn boundaries are NOT decided here — the caller's voice-activity detector
// owns that. This type only converts audio into a running transcript.

@available(macOS 26.0, *)
actor SpeechTranscriberBridge {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    private var finalizedText = ""
    private var volatileText = ""

    /// Called on every transcript change with the best current text.
    private var onUpdate: (@Sendable (String) -> Void)?

    var currentTranscript: String {
        (finalizedText + " " + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when this locale is supported on-device. Installation is handled
    /// on first use, so "supported" is the meaningful gate here.
    static func isAvailable(locale: Locale = Locale(identifier: "en-US")) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = locale.identifier(.bcp47)
        return supported.contains { $0.identifier(.bcp47) == wanted }
    }

    func start(locale: Locale = Locale(identifier: "en-US"),
               onUpdate: @escaping @Sendable (String) -> Void) async throws {
        await stop()
        self.onUpdate = onUpdate
        finalizedText = ""
        volatileText = ""

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        // Make sure the on-device model is present; this is a no-op once cached.
        if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try? await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await self.ingest(text: text, isFinal: result.isFinal)
                }
            } catch {
                FlightRecorder.logError(
                    source: "speech-transcriber",
                    message: error.localizedDescription
                )
            }
        }

        try await analyzer.start(inputSequence: stream)
    }

    private func ingest(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText = (finalizedText + " " + text).trimmingCharacters(in: .whitespaces)
            volatileText = ""
        } else {
            volatileText = text
        }
        onUpdate?(currentTranscript)
    }

    /// Feed a microphone buffer. Converts to the analyzer's preferred format
    /// when the mic's native format differs (it usually does).
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let continuation = inputContinuation else { return }
        guard let target = analyzerFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if buffer.format == target {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        guard let converted = convert(buffer, to: target) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter == nil || converter?.outputFormat != target || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            FlightRecorder.logError(source: "speech-transcriber:convert", message: error.localizedDescription)
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    /// Clear the transcript between turns without tearing down the analyzer —
    /// restarting it per turn would reintroduce startup latency on every reply.
    func resetTurn() {
        finalizedText = ""
        volatileText = ""
    }

    /// Close the input, let the analyzer finish, and return the final text.
    func finish() async -> String {
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        let text = currentTranscript
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        return text
    }

    func stop() async {
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        converter = nil
        finalizedText = ""
        volatileText = ""
    }
}
