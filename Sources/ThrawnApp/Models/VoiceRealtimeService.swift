@preconcurrency import AVFoundation
import Foundation

// MARK: - Voice Realtime Service (speech-to-speech)
//
// Tiers 1 and 2 make the cascade fast: microphone → transcript → model →
// synthesized speech. Every stage still waits for the one before it, and the
// model only ever sees text, so tone, pacing, and interruptions are lost.
//
// This is the non-cascading path. Audio goes straight to a speech-native
// model and audio comes straight back — no transcription step, no TTS step.
// Turn-taking is detected server-side, so barge-in is native rather than
// something we bolt on with an echo canceller. Function calls arrive in the
// same stream, so the model can operate the board mid-conversation.
//
// The link is credential-gated. With no key present this type stays inert and
// the fast lane handles every turn, so voice never depends on it being set up.

@MainActor
final class VoiceRealtimeService: NSObject, ObservableObject {

    @Published private(set) var isConnected = false
    @Published private(set) var isConfigured = false
    @Published private(set) var statusText = "Realtime not configured."
    @Published private(set) var lastUserTranscript = ""
    @Published private(set) var lastAssistantTranscript = ""

    /// User preference: use realtime when it's available.
    @Published var preferred: Bool = true {
        didSet { persistPreference() }
    }

    /// Reports assistant speaking state so the console chrome can react.
    var onModeChange: ((Bool) -> Void)?

    private weak var tools: VoiceTools?

    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?

    // Audio: capture at the model's native 24 kHz PCM16, play the same back.
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var captureConverter: AVAudioConverter?
    private var audioReady = false
    private var pendingPlaybackFrames = 0

    private static let model = "gpt-realtime"
    private static let sampleRate: Double = 24_000

    private static let configFileName = "openai-realtime-config.json"
    private static let preferenceFileName = "voice-realtime-preference.json"

    // MARK: - Init

    init(tools: VoiceTools? = nil) {
        self.tools = tools
        super.init()
        loadPreference()
        refreshConfiguration()
    }

    func bind(tools: VoiceTools) { self.tools = tools }

    /// Where the key can live. Never read from the chat transcript — the user
    /// drops it into their own environment or config file.
    private func loadAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }
        let url = ThrawnPaths.appSupportDir.appendingPathComponent(Self.configFileName)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let key = json["apiKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    func refreshConfiguration() {
        isConfigured = loadAPIKey() != nil
        if !isConfigured {
            statusText = "Realtime not configured — add an OpenAI key to enable."
        } else if !isConnected {
            statusText = "Realtime ready."
        }
    }

    // MARK: - Connection

    func connect() async {
        guard !isConnected else { return }
        guard let key = loadAPIKey() else {
            statusText = "Realtime not configured."
            return
        }

        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: Self.model)]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        self.session = session
        let socket = session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()

        isConnected = true
        statusText = "Realtime connecting…"
        FlightRecorder.logEvent(category: "voice-realtime", action: "connect", detail: Self.model)

        startReceiveLoop()
        await configureSession()
        startAudio()
    }

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session = nil
        stopAudio()
        isConnected = false
        onModeChange?(false)
        statusText = isConfigured ? "Realtime ready." : "Realtime not configured."
        FlightRecorder.logEvent(category: "voice-realtime", action: "disconnect", detail: "closed")
    }

    /// Stop the model mid-sentence — used when the user talks over it.
    func cancelResponse() {
        guard isConnected else { return }
        send(["type": "response.cancel"])
        playerNode.stop()
        pendingPlaybackFrames = 0
        if playerNode.engine != nil, engine.isRunning { playerNode.play() }
        onModeChange?(false)
    }

    private func configureSession() async {
        let instructions = """
        You are Thrawn, Andrew's command agent for NDAI, speaking out loud.

        Be brief and conversational — one or two sentences unless asked for more. \
        Never read file paths, JSON, or code aloud. Refer to cards as "task twenty one", \
        not "TASK-021".

        Never invent board state, task numbers, agent activity, or product health. \
        Call a tool for any fact about the board, the agents, or the products. \
        If a request needs deep reasoning, external sends, credentials, or business \
        judgment, say you're taking it to the board and create a card instead of guessing.

        Andrew's stable: Thrawn (command), Dwight (router), Samwell Tarly (SandPro OMP), \
        Sir Davos (Hit Zero), Steven (Spas 360).
        """

        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["audio", "text"],
                "instructions": instructions,
                "voice": "cedar",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1"],
                // Server-side turn detection is what makes interruption native.
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 600,
                    "create_response": true,
                ],
                "tools": VoiceTools.realtimeSchemas,
                "tool_choice": "auto",
                "temperature": 0.7,
            ] as [String: Any],
        ]
        send(payload)
    }

    // MARK: - Socket plumbing

    private func send(_ payload: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { error in
            if let error {
                FlightRecorder.logError(source: "voice-realtime:send", message: error.localizedDescription)
            }
        }
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while let self, self.isConnected, !Task.isCancelled {
                guard let socket = self.socket else { break }
                do {
                    let message = try await socket.receive()
                    switch message {
                    case .string(let text):
                        self.handleEvent(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleEvent(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    FlightRecorder.logError(source: "voice-realtime:receive", message: error.localizedDescription)
                    self.statusText = "Realtime link dropped."
                    await self.disconnect()
                    break
                }
            }
        }
    }

    private func handleEvent(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            statusText = "Realtime live — just talk."

        case "input_audio_buffer.speech_started":
            // The user started talking; kill any audio still playing.
            playerNode.stop()
            pendingPlaybackFrames = 0
            if engine.isRunning { playerNode.play() }
            onModeChange?(false)

        case "conversation.item.input_audio_transcription.completed":
            if let text = event["transcript"] as? String {
                lastUserTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

        case "response.audio.delta", "response.output_audio.delta":
            if let b64 = event["delta"] as? String { enqueueAudio(base64: b64) }

        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = event["delta"] as? String { lastAssistantTranscript += delta }

        case "response.audio_transcript.done", "response.output_audio_transcript.done":
            if let text = event["transcript"] as? String { lastAssistantTranscript = text }

        case "response.function_call_arguments.done":
            handleFunctionCall(event)

        case "response.created":
            lastAssistantTranscript = ""
            onModeChange?(true)

        case "response.done":
            onModeChange?(false)

        case "error":
            let message = ((event["error"] as? [String: Any])?["message"] as? String) ?? "unknown"
            statusText = "Realtime error: \(message)"
            FlightRecorder.logError(source: "voice-realtime", message: message)

        default:
            break
        }
    }

    // MARK: - Function calling

    private func handleFunctionCall(_ event: [String: Any]) {
        guard let name = event["name"] as? String,
              let callId = event["call_id"] as? String else { return }

        var args: [String: String] = [:]
        if let raw = event["arguments"] as? String,
           let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in parsed { args[key] = String(describing: value) }
        }

        let result = tools?.execute(name: name, arguments: args)
            ?? VoiceToolResult(spoken: "The tool layer isn't wired up.")

        send([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": result.spoken,
            ] as [String: Any],
        ])
        // Let the model narrate the result in its own voice.
        send(["type": "response.create"])
    }

    // MARK: - Audio capture

    private func startAudio() {
        guard !audioReady else {
            if !engine.isRunning { try? engine.start() }
            playerNode.play()
            return
        }

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { return }

        guard let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ) else { return }
        captureConverter = AVAudioConverter(from: inputFormat, to: captureFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.forwardCapturedAudio(buffer, to: captureFormat)
        }

        engine.prepare()
        do {
            try engine.start()
            playerNode.play()
            audioReady = true
        } catch {
            FlightRecorder.logError(source: "voice-realtime:audio", message: error.localizedDescription)
            statusText = "Realtime microphone unavailable."
        }
    }

    private func stopAudio() {
        guard audioReady else { return }
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        audioReady = false
        pendingPlaybackFrames = 0
    }

    nonisolated private func forwardCapturedAudio(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) {
        Task { @MainActor [weak self] in
            guard let self, let converter = self.captureConverter, self.isConnected else { return }

            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 512)
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0,
                  let channel = out.int16ChannelData else { return }

            let byteCount = Int(out.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: channel[0], count: byteCount)
            self.send([
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString(),
            ])
        }
    }

    // MARK: - Audio playback

    private func enqueueAudio(base64: String) {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channel = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        // PCM16 little-endian → normalized float samples.
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                channel[0][i] = Float(Int16(littleEndian: samples[i])) / 32768.0
            }
        }

        guard engine.isRunning else { return }
        pendingPlaybackFrames += frameCount
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingPlaybackFrames = max(0, self.pendingPlaybackFrames - frameCount)
            }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    // MARK: - Preference persistence

    private func loadPreference() {
        let url = ThrawnPaths.appSupportDir.appendingPathComponent(Self.preferenceFileName)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Bool],
              let value = json["preferred"] else { return }
        preferred = value
    }

    private func persistPreference() {
        let url = ThrawnPaths.appSupportDir.appendingPathComponent(Self.preferenceFileName)
        guard let data = try? JSONSerialization.data(withJSONObject: ["preferred": preferred]) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
