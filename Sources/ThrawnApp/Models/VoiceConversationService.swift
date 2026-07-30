import AppKit
import AVFoundation
import Combine
import Foundation
import Speech

// MARK: - Voice Conversation Service
//
// Owns the microphone and the shape of a spoken turn.
//
// The design goal is that talking to Thrawn feels like talking, not like
// operating a walkie-talkie. That means three things the old push-to-send
// version didn't do:
//
//   • The mic stays open for the whole session. Turn boundaries come from
//     voice-activity detection, not from the user toggling a key twice.
//   • Echo cancellation is on, so the mic can stay live while Thrawn speaks.
//     That is what makes barge-in possible — start talking and the reply cuts.
//   • Nothing polls. Transcription, turn dispatch, and escalated replies are
//     all event-driven, and replies stream into speech as they generate.
//
// Transcription uses macOS 26's on-device SpeechAnalyzer when present and
// falls back to SFSpeechRecognizer (forced on-device where supported) so the
// feature degrades rather than disappears on older systems.

@MainActor
final class VoiceConversationService: ObservableObject {

    enum Mode: String {
        case idle, listening, thinking, speaking

        var label: String {
            switch self {
            case .idle:      return "Caps Lock opens Thrawn voice."
            case .listening: return "Listening…"
            case .thinking:  return "Working…"
            case .speaking:  return "Thrawn is talking — speak to interrupt."
            }
        }
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var isSessionActive = false
    @Published private(set) var transcript = ""
    @Published private(set) var statusText = Mode.idle.label
    @Published private(set) var lastErrorText: String?
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var routeLabel = ""
    @Published private(set) var engineLabel = ""

    /// Kept for existing call sites and the overlay's visibility check.
    var isListening: Bool { mode == .listening || mode == .thinking }

    // MARK: Dependencies

    private weak var threadStore: ThreadStore?
    private weak var voiceService: VoiceService?
    private weak var nav: ConsoleNavigationStore?
    private var fastLane: VoiceFastLane?
    private var realtime: VoiceRealtimeService?
    private var tools: VoiceTools?

    // MARK: Audio

    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var voiceProcessingActive = false

    // MARK: Transcription

    private var modernBridge: Any?  // SpeechTranscriberBridge, gated by availability
    private var useModernTranscriber = false
    private let legacyRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?

    // MARK: Turn state

    private var turnActive = false          // user is mid-utterance
    private var lastVoiceAt = Date.distantPast
    private var consecutiveVoiceFrames = 0
    private var noiseFloor: Double = 0.004
    private var endpointTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var escalationCancellable: AnyCancellable?
    private var escalatedThreadId: UUID?
    private var spokenEscalationPrefix = ""

    /// Silence after speech that ends a turn. Long enough to survive a beat of
    /// thought mid-sentence, short enough not to feel like waiting.
    private let endpointSilence: TimeInterval = 0.75
    /// Consecutive loud frames needed to call it speech (rejects clicks/pops).
    private let onsetFrames = 3
    /// Higher bar while Thrawn is talking so his own voice can't trigger a turn.
    private let bargeInFrames = 6

    // MARK: Hotkey

    private var globalCapsMonitor: Any?
    private var localCapsMonitor: Any?
    private var lastCapsEventAt = Date.distantPast

    // MARK: - Wiring

    func bind(threadStore: ThreadStore, voiceService: VoiceService, nav: ConsoleNavigationStore) {
        self.threadStore = threadStore
        self.voiceService = voiceService
        self.nav = nav
        installCapsMonitorIfNeeded()
    }

    func bindVoiceStack(tools: VoiceTools, fastLane: VoiceFastLane, realtime: VoiceRealtimeService) {
        self.tools = tools
        self.fastLane = fastLane
        self.realtime = realtime
        fastLane.onEscalate = { [weak self] text in
            self?.escalateToCommandThread(text)
        }
        realtime.onModeChange = { [weak self] speaking in
            guard let self else { return }
            self.mode = speaking ? .speaking : .listening
            self.statusText = self.mode.label
        }
    }

    deinit {
        if let globalCapsMonitor { NSEvent.removeMonitor(globalCapsMonitor) }
        if let localCapsMonitor { NSEvent.removeMonitor(localCapsMonitor) }
    }

    // MARK: - Session control

    func toggleThrawnVoice() {
        if isSessionActive {
            endSession(reason: "user")
        } else {
            startSession()
        }
    }

    func cancelListening() { endSession(reason: "cancel") }

    func dismissOverlay() {
        endSession(reason: "dismiss")
        transcript = ""
        lastErrorText = nil
        routeLabel = ""
        statusText = Mode.idle.label
    }

    private func startSession() {
        Task { [weak self] in
            guard let self else { return }
            guard await self.ensurePermissions() else { return }

            self.focusCommandSurface()

            // Realtime is a full duplex speech-to-speech link — when it's
            // configured it replaces this entire capture/transcribe path.
            if let realtime = self.realtime, realtime.isConfigured, realtime.preferred {
                self.engineLabel = "realtime"
                self.isSessionActive = true
                self.mode = .listening
                self.statusText = "Realtime link opening…"
                await realtime.connect()
                return
            }

            await self.prepareTranscription()
            self.beginAudioCapture()
        }
    }

    private func endSession(reason: String) {
        endpointTask?.cancel(); endpointTask = nil
        turnTask?.cancel(); turnTask = nil
        escalationCancellable = nil
        escalatedThreadId = nil

        if let realtime, realtime.isConnected {
            Task { await realtime.disconnect() }
        }

        stopLegacyRecognition()
        if useModernTranscriber, #available(macOS 26.0, *),
           let bridge = modernBridge as? SpeechTranscriberBridge {
            Task { await bridge.stop() }
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        voiceService?.interruptForBargeIn()
        turnActive = false
        consecutiveVoiceFrames = 0
        audioLevel = 0
        isSessionActive = false
        mode = .idle
        statusText = Mode.idle.label
        FlightRecorder.logEvent(category: "voice-chat", action: "session-end", detail: reason)
    }

    private func focusCommandSurface() {
        NSApp.activate(ignoringOtherApps: true)
        nav?.selectSection(.command)
        transcript = ""
        lastErrorText = nil
    }

    // MARK: - Transcription setup

    private func prepareTranscription() async {
        if #available(macOS 26.0, *) {
            let bridge = SpeechTranscriberBridge()
            do {
                try await bridge.start(locale: Locale(identifier: "en-US")) { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.transcript = text
                    }
                }
                modernBridge = bridge
                useModernTranscriber = true
                engineLabel = "on-device · SpeechAnalyzer"
                FlightRecorder.logEvent(category: "voice-chat", action: "stt-engine", detail: "SpeechAnalyzer")
                return
            } catch {
                FlightRecorder.logEvent(
                    category: "voice-chat", action: "stt-fallback",
                    detail: "SpeechAnalyzer unavailable: \(error.localizedDescription)"
                )
            }
        }
        useModernTranscriber = false
        engineLabel = "on-device · SFSpeech"
    }

    // MARK: - Audio capture

    private func beginAudioCapture() {
        guard !audioEngine.isRunning else {
            isSessionActive = true
            mode = .listening
            statusText = Mode.listening.label
            return
        }

        let inputNode = audioEngine.inputNode

        // Echo cancellation. Without it the mic hears the speakers and every
        // reply would barge in on itself. This is the switch that makes an
        // always-open mic viable.
        if !voiceProcessingActive {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                voiceProcessingActive = true
            } catch {
                FlightRecorder.logEvent(
                    category: "voice-chat", action: "aec-unavailable",
                    detail: error.localizedDescription
                )
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastErrorText = "No usable microphone input format."
            statusText = "Voice unavailable."
            return
        }

        if tapInstalled {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            lastErrorText = "Could not start microphone: \(error.localizedDescription)"
            statusText = "Voice unavailable."
            FlightRecorder.logError(source: "voice-chat:start", message: error.localizedDescription)
            return
        }

        if !useModernTranscriber { startLegacyRecognition() }

        isSessionActive = true
        mode = .listening
        statusText = Mode.listening.label
        noiseFloor = 0.004
        FlightRecorder.logEvent(category: "voice-chat", action: "session-start", detail: engineLabel)
    }

    /// Audio-thread callback. Does only arithmetic here; every decision is
    /// handed to the main actor.
    nonisolated private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let channel = channelData[0]
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        let stride = max(1, frameLength / 256)
        var count = 0
        var i = 0
        while i < frameLength {
            let sample = channel[i]
            sum += sample * sample
            count += 1
            i += stride
        }
        let rms = Double(sqrt(sum / Float(max(count, 1))))
        let duration = Double(frameLength) / buffer.format.sampleRate

        Task { @MainActor [weak self] in
            self?.processLevel(rms: rms, duration: duration, buffer: buffer)
        }
    }

    private func processLevel(rms: Double, duration: TimeInterval, buffer: AVAudioPCMBuffer) {
        guard isSessionActive else { return }

        // Feed whichever transcriber is live.
        if useModernTranscriber, #available(macOS 26.0, *),
           let bridge = modernBridge as? SpeechTranscriberBridge {
            Task { await bridge.append(buffer) }
        } else {
            legacyRequest?.append(buffer)
        }

        audioLevel = (audioLevel * 0.62) + (min(1.0, rms * 18.0) * 0.38)

        // Adaptive floor: track the quiet baseline so a noisy room raises the
        // bar instead of producing endless false turns.
        let threshold = max(noiseFloor * 3.2, 0.011)
        let isVoice = rms > threshold
        if !isVoice {
            noiseFloor = (noiseFloor * 0.97) + (rms * 0.03)
        }

        let thrawnTalking = voiceService?.isSpeaking ?? false
        let requiredFrames = thrawnTalking ? bargeInFrames : onsetFrames

        if isVoice {
            consecutiveVoiceFrames += 1
            lastVoiceAt = Date()

            if consecutiveVoiceFrames >= requiredFrames {
                if thrawnTalking {
                    // Barge-in: user talked over the reply.
                    voiceService?.interruptForBargeIn()
                    realtime?.cancelResponse()
                    mode = .listening
                    statusText = Mode.listening.label
                }
                if !turnActive && mode != .thinking {
                    beginTurn()
                }
            }
        } else {
            consecutiveVoiceFrames = 0
            if turnActive, Date().timeIntervalSince(lastVoiceAt) >= endpointSilence {
                endTurn()
            }
        }
    }

    // MARK: - Turn lifecycle

    private func beginTurn() {
        turnActive = true
        mode = .listening
        statusText = Mode.listening.label
        if useModernTranscriber, #available(macOS 26.0, *),
           let bridge = modernBridge as? SpeechTranscriberBridge {
            Task { await bridge.resetTurn() }
        }
    }

    private func endTurn() {
        guard turnActive else { return }
        turnActive = false

        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard spoken.count >= 2 else {
            transcript = ""
            return
        }

        mode = .thinking
        statusText = Mode.thinking.label
        FlightRecorder.logEvent(category: "voice-chat", action: "turn", detail: spoken.prefix(120).description)

        // Legacy engine needs a fresh request per turn; the modern one keeps
        // running and was already reset at turn start.
        if !useModernTranscriber {
            restartLegacyRecognition()
        }

        turnTask?.cancel()
        turnTask = Task { [weak self] in
            guard let self, let lane = self.fastLane else { return }
            await lane.handle(utterance: spoken)
            await MainActor.run {
                self.routeLabel = lane.lastRouteLabel
                self.transcript = ""
                if self.isSessionActive && self.mode == .thinking {
                    self.mode = .listening
                    self.statusText = Mode.listening.label
                }
            }
        }
    }

    // MARK: - Escalation to the command thread
    //
    // When the fast lane hands off, the deep route's reply is streamed into
    // speech as it generates rather than waiting for the whole response.

    private func escalateToCommandThread(_ text: String) {
        guard let threadStore else { return }
        threadStore.sendMessage(text)
        guard let threadId = threadStore.selectedThreadId else { return }
        escalatedThreadId = threadId
        spokenEscalationPrefix = ""
        mode = .speaking
        statusText = "Command is answering…"

        escalationCancellable = threadStore.$threads
            .receive(on: RunLoop.main)
            .sink { [weak self] threads in
                guard let self, let thread = threads.first(where: { $0.id == threadId }) else { return }
                let reply = thread.messages.last(where: { $0.role == .assistant })?.text ?? ""
                guard !reply.isEmpty else { return }

                if self.spokenEscalationPrefix.isEmpty {
                    self.voiceService?.beginStreamingTurn(agentId: "thrawn")
                }
                if reply.count > self.spokenEscalationPrefix.count,
                   reply.hasPrefix(self.spokenEscalationPrefix) {
                    let delta = String(reply.dropFirst(self.spokenEscalationPrefix.count))
                    self.voiceService?.appendStreamingDelta(delta)
                    self.spokenEscalationPrefix = reply
                }

                if !thread.isLoading {
                    self.voiceService?.endStreamingTurn()
                    self.escalationCancellable = nil
                    self.escalatedThreadId = nil
                    self.spokenEscalationPrefix = ""
                    if self.isSessionActive {
                        self.mode = .listening
                        self.statusText = Mode.listening.label
                    }
                }
            }
    }

    // MARK: - Legacy recognizer path

    private func startLegacyRecognition() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        // Keeping recognition on-device removes a network round trip from
        // every turn and keeps board content off third-party servers.
        if legacyRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = Self.customVocabulary
        legacyRequest = request

        legacyTask = legacyRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error, self.isSessionActive, self.turnActive {
                    FlightRecorder.logEvent(
                        category: "voice-chat", action: "legacy-recognition-note",
                        detail: error.localizedDescription
                    )
                }
            }
        }
    }

    private func restartLegacyRecognition() {
        stopLegacyRecognition()
        startLegacyRecognition()
    }

    private func stopLegacyRecognition() {
        legacyRequest?.endAudio()
        legacyTask?.cancel()
        legacyTask = nil
        legacyRequest = nil
    }

    /// Words the generic language model reliably mangles: agent names, product
    /// names, and the board's own vocabulary.
    static let customVocabulary: [String] = [
        "Thrawn", "Dwight", "Samwell Tarly", "Sir Davos", "Steven",
        "SandPro", "SandPro OMP", "Hit Zero", "Spas 360", "Cyclops", "Vaultage",
        "NDAI", "Buckshot", "Citadel", "Clarity", "Supabase", "Vercel",
        "heartbeat", "flow board", "blocked lane", "proof run", "verdict",
        "task board", "objective", "patrol", "deliverable", "autonomy ladder",
    ]

    // MARK: - Permissions

    private func ensurePermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else {
            lastErrorText = "Speech recognition permission is required for Thrawn voice."
            statusText = "Speech permission needed."
            return false
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .authorized { return true }
        if micStatus == .notDetermined {
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
            if granted { return true }
        }
        lastErrorText = "Microphone permission is required for Thrawn voice."
        statusText = "Microphone permission needed."
        return false
    }

    // MARK: - Caps Lock hotkey

    private func installCapsMonitorIfNeeded() {
        guard globalCapsMonitor == nil, localCapsMonitor == nil else { return }

        globalCapsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleFlagsChanged(event) }
        }
        localCapsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleFlagsChanged(event) }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == 57 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCapsEventAt) > 0.30 else { return }
        lastCapsEventAt = now
        toggleThrawnVoice()
    }
}
