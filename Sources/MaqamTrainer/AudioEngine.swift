import Foundation
import AVFoundation
import Combine

/// One oscillator voice of the tone player.
private final class ToneVoice {
    var frequency: Double = 440.0
    var phase: Double = 0.0
    var amplitude: Float = 0.22
    var isOn: Bool = false
}

/// Mutable state shared with the real-time render callback of the tone
/// player. Written from the main thread, read on the audio thread.
/// Voice 0 plays one-shot tones (guide notes, scales); voices 1...3 are
/// the vocal trainer's sustained drone layers (base, fifth, octave).
private final class ToneState {
    var voices: [ToneVoice] = [ToneVoice(), ToneVoice(), ToneVoice(), ToneVoice()]
}

/// Live microphone pitch coach + quarter-tone-exact tone player.
///
/// - Listening: AVAudioSession (.playAndRecord / .measurement) and an
///   AVAudioEngine input tap (4096-frame buffers). Pitch is estimated with
///   normalized autocorrelation + parabolic interpolation, then mapped to
///   the nearest degree of the currently selected maqam.
/// - Playing: an AVAudioSourceNode renders a sine with harmonics at any
///   exact frequency, so quarter tones are pitch-exact.
final class AudioEngine: ObservableObject {

    // MARK: Published state

    @Published var detectedFrequency: Double = 0
    @Published var detectedNoteName: String = "—"
    /// 0-based index of the nearest scale degree (octave tonic reports 0).
    @Published var detectedDegreeIndex: Int = 0
    /// Deviation from the nearest scale degree, in cents (-50...+50).
    @Published var centsDeviation: Double = 0
    /// Smoothed RMS input level, roughly 0...0.5 for speech/singing.
    @Published var level: Float = 0
    @Published var isListening: Bool = false
    @Published var permissionDenied: Bool = false
    /// Raw pitch of the latest capture buffer as fractional MIDI
    /// (quarter-tone precise, independent of any maqam), or nil when the
    /// latest buffer carried no confident pitch. Consumed by the vocal
    /// trainer; updated once per capture buffer while listening.
    @Published var rawMidi: Double? = nil

    // MARK: Private state

    private let captureEngine = AVAudioEngine()
    private let toneEngine = AVAudioEngine()
    private let toneState = ToneState()
    private var toneNode: AVAudioSourceNode?
    private var currentMaqam: Maqam = Maqam.all[0]

    func setMaqam(_ maqam: Maqam) {
        currentMaqam = maqam
    }

    // MARK: Permission

    func requestRecordPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionDenied = !granted
                completion(granted)
            }
        }
    }

    // MARK: Listening

    func startListening() {
        if isListening { return }
        requestRecordPermission { [weak self] granted in
            guard let self = self, granted else { return }
            self.beginCapture()
        }
    }

    private func beginCapture() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return
        }

        let input = captureEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        captureEngine.prepare()
        do {
            try captureEngine.start()
            DispatchQueue.main.async { self.isListening = true }
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    func stopListening() {
        captureEngine.stop()
        captureEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async {
            self.isListening = false
            self.level = 0
            self.rawMidi = nil
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        let sampleRate = buffer.format.sampleRate

        var sumSquares: Float = 0
        for s in samples { sumSquares += s * s }
        let rms = sqrt(sumSquares / Float(frameCount))

        let maqam = currentMaqam
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.level = self.level * 0.6 + rms * 0.4
            if rms < 0.008 {
                self.detectedFrequency = 0
                self.detectedNoteName = "—"
                self.centsDeviation = 0
                self.rawMidi = nil
                return
            }
            guard let frequency = Self.detectPitch(samples: samples, sampleRate: sampleRate) else {
                self.rawMidi = nil
                return
            }
            self.detectedFrequency = frequency
            self.rawMidi = 69.0 + 12.0 * log2(frequency / 440.0)

            // Position inside the octave above the tonic, in cents.
            var wrapped = (1200.0 * log2(frequency / maqam.tonicFrequency))
                .truncatingRemainder(dividingBy: 1200.0)
            if wrapped < 0 { wrapped += 1200.0 }

            // Nearest scale degree (the octave tonic counts as degree 0).
            var bestIndex = 0
            var bestDeviation = wrapped
            for (index, degreeCents) in maqam.scaleCents.enumerated() {
                let deviation = wrapped - Double(degreeCents)
                if abs(deviation) < abs(bestDeviation) {
                    bestDeviation = deviation
                    bestIndex = index
                }
            }
            if abs(wrapped - 1200.0) < abs(bestDeviation) {
                bestDeviation = wrapped - 1200.0
                bestIndex = 0
            }
            self.detectedDegreeIndex = bestIndex
            self.centsDeviation = bestDeviation
            self.detectedNoteName = maqam.noteName(forDegree: bestIndex)
        }
    }

    /// Normalized autocorrelation pitch estimate with parabolic
    /// interpolation of the peak. Returns nil when the frame is not
    /// confidently periodic.
    static func detectPitch(samples: [Float], sampleRate: Double) -> Double? {
        let n = samples.count
        guard n > 1024 else { return nil }

        // Remove DC.
        var mean: Double = 0
        for s in samples { mean += Double(s) }
        mean /= Double(n)
        var x = [Double](repeating: 0, count: n)
        var energy: Double = 0
        for i in 0..<n {
            x[i] = Double(samples[i]) - mean
            energy += x[i] * x[i]
        }
        guard energy > 0 else { return nil }

        let minLag = max(2, Int(sampleRate / 1200.0))   // up to 1200 Hz
        let maxLag = min(n - 2, Int(sampleRate / 60.0)) // down to 60 Hz
        guard maxLag > minLag else { return nil }

        var correlations = [Double](repeating: 0, count: maxLag + 2)
        var bestLag = -1
        var bestValue: Double = 0
        for lag in minLag...maxLag {
            var sum: Double = 0
            let limit = n - lag
            for i in 0..<limit { sum += x[i] * x[i + lag] }
            let value = sum / energy
            correlations[lag] = value
            if value > bestValue {
                bestValue = value
                bestLag = lag
            }
        }
        guard bestLag > minLag, bestValue > 0.5 else { return nil }

        // Parabolic interpolation around the peak.
        let alpha = correlations[bestLag - 1]
        let beta = correlations[bestLag]
        let gamma = correlations[bestLag + 1]
        let denominator = alpha - 2.0 * beta + gamma
        var shift: Double = 0
        if denominator != 0 {
            shift = 0.5 * (alpha - gamma) / denominator
        }
        return sampleRate / (Double(bestLag) + shift)
    }

    // MARK: Tone player

    private func setupToneIfNeeded() {
        if toneNode != nil { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            return
        }
        let state = toneState
        let node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, outputData in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let sampleRate = 44100.0
            for frame in 0..<Int(frameCount) {
                var value: Float = 0
                for voice in state.voices where voice.isOn {
                    voice.phase += 2.0 * Double.pi * voice.frequency / sampleRate
                    if voice.phase > 2.0 * Double.pi { voice.phase -= 2.0 * Double.pi }
                    // Fundamental + two harmonics: a plain, pitch-clear tone.
                    value += Float(sin(voice.phase)
                                   + 0.35 * sin(2.0 * voice.phase)
                                   + 0.12 * sin(3.0 * voice.phase)) * voice.amplitude
                }
                for buffer in buffers {
                    if let data = buffer.mData {
                        data.assumingMemoryBound(to: Float.self)[frame] = value
                    }
                }
            }
            isSilence.pointee = false
            return noErr
        }
        toneEngine.attach(node)
        toneEngine.connect(node, to: toneEngine.mainMixerNode, format: format)
        toneNode = node
    }

    /// Session + engine setup shared by one-shot tones and the drone.
    private func ensureToneEngineRunning() {
        setupToneIfNeeded()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.defaultToSpeaker])
        try? session.setActive(true)
        toneEngine.prepare()
        if !toneEngine.isRunning {
            try? toneEngine.start()
        }
    }

    /// Play one tone at an exact frequency (quarter tones included).
    func playTone(frequency: Double, duration: Double = 0.55) {
        ensureToneEngineRunning()
        toneState.voices[0].frequency = frequency
        toneState.voices[0].isOn = true
        let state = toneState
        DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
            state.voices[0].isOn = false
        }
    }

    // MARK: Drone (vocal trainer)

    /// Start or update the sustained reference drone on voices 1...3:
    /// the base note, optionally its fifth (+700 cents) and its octave,
    /// at the same relative levels as the web trainer (0.20 / 0.10 / 0.08).
    func startDrone(baseFrequency: Double, fifth: Bool, octave: Bool) {
        ensureToneEngineRunning()
        let base = toneState.voices[1]
        base.frequency = baseFrequency
        base.amplitude = 0.20
        base.isOn = true
        let fifthVoice = toneState.voices[2]
        fifthVoice.frequency = baseFrequency * pow(2.0, 700.0 / 1200.0)
        fifthVoice.amplitude = 0.10
        fifthVoice.isOn = fifth
        let octaveVoice = toneState.voices[3]
        octaveVoice.frequency = baseFrequency * 2.0
        octaveVoice.amplitude = 0.08
        octaveVoice.isOn = octave
    }

    /// Silence all drone layers (one-shot tones are not affected).
    func stopDrone() {
        for index in 1..<toneState.voices.count {
            toneState.voices[index].isOn = false
        }
    }

    /// Play the maqam's scale up then down, 0.6 s per note.
    func playScale(of maqam: Maqam) {
        Task { [weak self] in
            guard let self = self else { return }
            let up = Array(0...(maqam.scaleCents.count - 1))
            let down = Array(up.dropLast().reversed())
            for index in up + down {
                self.playTone(frequency: maqam.frequency(forDegree: index), duration: 0.55)
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }
}
