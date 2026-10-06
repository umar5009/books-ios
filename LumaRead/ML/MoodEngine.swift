import Foundation
import AVFoundation
import Speech
import NaturalLanguage

/// Senses the reader's mood from *what* they say (on-device speech-to-text + sentiment + optional
/// Core ML emotion classifier), *how* they say it (voice energy & speaking rate) and, if the camera
/// is on, their facial expression (ARKit blend shapes).
@MainActor
final class MoodEngine: ObservableObject {
    enum Phase: Equatable { case idle, listening, analyzing, done }

    @Published var phase: Phase = .idle
    @Published var transcript = ""
    @Published var level: Float = 0            // live mic level 0...1 for the orb animation
    @Published var mood: Mood?
    @Published var confidence: Double = 0
    @Published var explanation = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var energySamples: [Float] = []
    private var startedAt = Date()

    /// Optional Core ML text classifier (train with Tools/TrainMoodClassifier.swift and drop
    /// MoodClassifier.mlmodel into the project). Falls back to the built-in model when absent.
    private lazy var customModel: NLModel? = {
        guard let url = Bundle.main.url(forResource: "MoodClassifier", withExtension: "mlmodelc") else { return nil }
        return try? NLModel(contentsOf: url)
    }()

    // MARK: Permissions

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    // MARK: Listening

    func startListening() async {
        errorMessage = nil
        guard await requestPermissions() else {
            errorMessage = "Microphone or speech permission is off. You can type how you feel instead."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        transcript = ""; energySamples = []; mood = nil; startedAt = .now

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true } // privacy
            request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                req.append(buffer)
                let rms = Self.rms(buffer)
                Task { @MainActor in
                    guard let self else { return }
                    self.level = min(1, rms * 12)
                    self.energySamples.append(rms)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            phase = .listening

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || (result?.isFinal ?? false) { self.stopAudio() }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            stopAudio()
        }
    }

    func stopAndAnalyze(expression: FaceExpression?) {
        let duration = Date().timeIntervalSince(startedAt)
        stopAudio()
        analyze(text: transcript, duration: duration, expression: expression)
    }

    func analyze(text: String, duration: TimeInterval = 0, expression: FaceExpression? = nil) {
        phase = .analyzing
        let energy = energySamples.isEmpty ? nil : energySamples.reduce(0, +) / Float(energySamples.count)
        let words = text.split(separator: " ").count
        let wps = duration > 1 ? Double(words) / duration : nil
        let result = Self.classify(text: text, energy: energy, wordsPerSecond: wps,
                                   expression: expression, customModel: customModel)
        mood = result.mood
        confidence = result.confidence
        explanation = result.why
        phase = .done
    }

    func reset() { stopAudio(); phase = .idle; transcript = ""; mood = nil; level = 0 }

    private func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return sqrt(sum / Float(n))
    }

    // MARK: - Multimodal fusion classifier

    struct Classification { let mood: Mood; let confidence: Double; let why: String }

    nonisolated static func classify(text: String, energy: Float?, wordsPerSecond: Double?,
                                     expression: FaceExpression?, customModel: NLModel?) -> Classification {
        var score: [Mood: Double] = Dictionary(uniqueKeysWithValues: Mood.allCases.map { ($0, 0.1) })
        var reasons: [String] = []
        let lower = text.lowercased()

        // 1) Lexicon layer
        for m in Mood.allCases {
            let hits = m.lexicon.filter { lower.contains($0) }.count
            score[m, default: 0] += Double(hits) * 1.2
        }

        // 2) Apple's on-device sentiment model (-1 ... 1)
        var sentiment = 0.0
        if !text.isEmpty {
            let tagger = NLTagger(tagSchemes: [.sentimentScore])
            tagger.string = text
            let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            sentiment = Double(tag?.rawValue ?? "0") ?? 0
            if sentiment > 0.3 { score[.joyful]! += 1.2 * sentiment; score[.calm]! += 0.5; reasons.append("positive words") }
            if sentiment < -0.3 {
                score[.melancholy]! += 1.0 * -sentiment; score[.stressed]! += 0.7 * -sentiment
                reasons.append("a heavier tone")
            }
        }

        // 3) Optional custom Core ML emotion model
        if let customModel, !text.isEmpty {
            let hyp = customModel.predictedLabelHypotheses(for: text, maximumCount: 3)
            for (label, p) in hyp { if let m = Mood(rawValue: label) { score[m, default: 0] += p * 3 } }
            reasons.append("the emotion model")
        }

        // 4) Prosody: loudness and pace
        if let energy {
            if energy > 0.08 { score[.joyful]! += 0.6; score[.adventurous]! += 0.6; score[.stressed]! += 0.3; reasons.append("lively voice") }
            if energy < 0.02 { score[.tired]! += 0.8; score[.calm]! += 0.4; score[.melancholy]! += 0.3; reasons.append("a quiet voice") }
        }
        if let wps = wordsPerSecond {
            if wps > 3.2 { score[.stressed]! += 0.7; score[.adventurous]! += 0.3; reasons.append("fast pace") }
            if wps < 1.6 { score[.tired]! += 0.5; score[.calm]! += 0.4 }
        }

        // 5) Face (ARKit blend shapes)
        if let e = expression {
            if e.smile > 0.35 { score[.joyful]! += 1.0; score[.romantic]! += 0.3; reasons.append("your smile") }
            if e.frown > 0.25 { score[.melancholy]! += 0.8 }
            if e.browDown > 0.35 { score[.stressed]! += 0.8; reasons.append("a furrowed brow") }
            if e.eyesHalfClosed > 0.4 { score[.tired]! += 0.9; reasons.append("heavy eyelids") }
        }

        if lower.contains("?") || lower.hasPrefix("what") || lower.hasPrefix("how") { score[.curious]! += 0.5 }

        let total = score.values.reduce(0, +)
        let best = score.max { $0.value < $1.value }!
        let conf = total > 0 ? best.value / total : 0
        let why = reasons.isEmpty ? "Based on what you said." : "I noticed " + reasons.prefix(3).joined(separator: ", ") + "."
        return Classification(mood: best.key, confidence: conf, why: why)
    }
}
