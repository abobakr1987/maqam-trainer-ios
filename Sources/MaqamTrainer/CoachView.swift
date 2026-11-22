import SwiftUI
import Combine

/// The live coach: pick a maqam, listen live, and get corrected against
/// the current target scale degree in real time.
struct CoachView: View {
    @EnvironmentObject private var engine: AudioEngine
    @State private var selectedMaqam: Maqam = Maqam.all[0]
    /// 0-based index of the scale degree the student should sing/play now.
    @State private var targetStep: Int = 0

    private var isOnTarget: Bool {
        engine.isListening
            && engine.detectedFrequency > 0
            && engine.detectedDegreeIndex == targetStep
            && abs(engine.centsDeviation) <= 15
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("المقام", selection: $selectedMaqam) {
                    ForEach(Maqam.all) { maqam in
                        Text(maqam.nameArabic).tag(maqam)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedMaqam) { newValue in
                    engine.setMaqam(newValue)
                    targetStep = 0
                }

                // Scale degrees with English note names; target highlighted.
                HStack(spacing: 6) {
                    ForEach(Array(selectedMaqam.degreeNames.enumerated()), id: \.offset) { index, name in
                        Text(name)
                            .font(.caption2)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .background(index == targetStep ? Color.orange.opacity(0.85) : Color.gray.opacity(0.15))
                            .cornerRadius(6)
                    }
                }

                Text("المطلوب دلوقتي: \(selectedMaqam.degreeNames[targetStep])")
                    .font(.headline)

                // Big detected note.
                VStack(spacing: 4) {
                    Text(engine.detectedNoteName)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    if engine.detectedFrequency > 0 {
                        Text(String(format: "%.1f Hz", engine.detectedFrequency))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("غنّي أو اعزف قدام المايك")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isOnTarget ? Color.green.opacity(0.25) : Color.gray.opacity(0.08))
                .cornerRadius(16)

                if isOnTarget {
                    Text("✅ صح")
                        .font(.title2).bold()
                        .foregroundColor(.green)
                }

                // Cents deviation bar, -50 ... +50.
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let clamped = max(-50.0, min(50.0, engine.centsDeviation))
                        let x = geo.size.width / 2 + CGFloat(clamped) / 50.0 * (geo.size.width / 2)
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 14)
                            Rectangle()
                                .fill(Color.secondary)
                                .frame(width: 2, height: 22)
                            Circle()
                                .fill(isOnTarget ? Color.green : Color.orange)
                                .frame(width: 18, height: 18)
                                .position(x: x, y: geo.size.height / 2)
                        }
                    }
                    .frame(height: 24)
                    Text(String(format: "%+.0f cents", engine.centsDeviation))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Live level meter.
                VStack(spacing: 4) {
                    ProgressView(value: Double(min(engine.level * 3.0, 1.0)))
                        .tint(.orange)
                    Text("مستوى صوتك")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if engine.permissionDenied {
                    Text("⚠ إذن المايك مرفوض — فعّله من: الإعدادات > الخصوصية والأمان > الميكروفون")
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button(engine.isListening ? "⏹ أوقف الاستماع" : "🎤 ابدأ الاستماع") {
                        if engine.isListening {
                            engine.stopListening()
                        } else {
                            engine.startListening()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("🔊 اسمع السلّم") {
                        engine.playScale(of: selectedMaqam)
                    }
                    .buttonStyle(.bordered)
                }

                Button("الخطوة اللي بعدها ⏭") {
                    targetStep = (targetStep + 1) % selectedMaqam.scaleCents.count
                }
                .buttonStyle(.bordered)

                Divider()
                    .padding(.top, 8)

                // Vocal Trainer (guided exercises, hold meter, drone,
                // range finder) — shares this coach's microphone session.
                VocalTrainerView()
            }
            .padding()
        }
        .navigationTitle("المدرب اللايف")
        .onAppear { engine.setMaqam(selectedMaqam) }
    }
}

// MARK: - Vocal Trainer (ported from the web «مدرّب الصوت»)

/// Median-of-recent-frames pitch smoother, mirroring the web trainer's
/// PitchSmoother: a pitch counts as stable when at least 3 of the last 5
/// frames agree on the same quarter-tone. A nil input clears the history
/// (and means "no detected pitch"); a non-nil input that is not yet
/// stable returns nil and the caller keeps the previous stable value.
private final class PitchSmoother {
    private var history: [Double] = []

    func push(_ midi: Double?) -> Double? {
        guard let midi = midi else {
            history = []
            return nil
        }
        history.append(midi)
        if history.count > 5 { history.removeFirst() }
        if history.count < 3 { return nil }
        let sorted = history.sorted()
        let median = sorted[sorted.count / 2]
        let quarter = (median * 2).rounded() / 2
        let agreeing = history.filter { abs(($0 * 2).rounded() / 2 - quarter) < 0.01 }.count
        return agreeing >= 3 ? median : nil
    }

    func reset() { history = [] }
}

private enum ExercisePhase {
    case idle, playing, listening, between, finished
}

private enum RangeMode {
    case idle, low, high, done
}

private enum PendingStart {
    case none, exercise, range
}

private struct ExerciseNote {
    let label: String
    /// Target as fractional MIDI (quarter-tone exact).
    let targetMidi: Double
    let frequency: Double
}

private struct ExerciseResult {
    let label: String
    let score: Int
    let avgCents: Int
    let heard: Bool
}

/// The Vocal Trainer section of the coach: live quarter-tone readout,
/// steady-hold meter, reference drone, guided maqam exercise with
/// scoring, and a vocal range finder. It consumes the engine's raw
/// pitch stream (`rawMidi`) — independent of the coach's maqam mapping —
/// and shares the coach's single microphone session, so starting an
/// exercise never fights the free-practice mode above.
private struct VocalTrainerView: View {
    @EnvironmentObject private var engine: AudioEngine

    // Live readout + hold meter.
    @State private var smoother = PitchSmoother()
    @State private var detectedMidi: Double? = nil
    @State private var holdQuarter: Double? = nil
    @State private var holdSince: Date? = nil
    @State private var holdSeconds: Double = 0
    @State private var holdBest: Double = 0

    // Drone.
    @State private var droneMidi: Double = 48
    @State private var droneFifth: Bool = false
    @State private var droneOctave: Bool = false
    @State private var droneOn: Bool = false

    // Guided exercise.
    @State private var exMaqam: Maqam = Maqam.all[0]
    @State private var exTonicMidi: Double = 53
    @State private var exRounds: Int = 1
    @State private var exSpeedMs: Int = 2600
    @State private var exAccuracy: Int = 25
    @State private var exActive: Bool = false
    @State private var exPhase: ExercisePhase = .idle
    @State private var exSequence: [ExerciseNote] = []
    @State private var exIndex: Int = 0
    @State private var exPhaseEnd: Date = .distantPast
    @State private var exMutedUntil: Date = .distantPast
    @State private var exListenEnd: Date = .distantPast
    @State private var exFrames: Int = 0
    @State private var exInFrames: Int = 0
    @State private var exCentsSum: Double = 0
    @State private var exResults: [ExerciseResult] = []
    @State private var exAllCents: [Double] = []
    @State private var exLastMessage: String = ""
    @State private var exFinalScore: Int? = nil
    @State private var exTendency: String = ""

    // Range finder.
    @State private var rangeMode: RangeMode = .idle
    @State private var rangeLow: Double? = nil
    @State private var rangeHigh: Double? = nil
    @State private var rangeCandidate: Double? = nil
    @State private var rangeCandidateSince: Date? = nil
    @State private var rangeStatus: String = "المايك لازم يكون شغال — شغّله من زرار «ابدأ الاستماع» فوق أو من زرار البدء هنا على طول."

    // Start requests waiting for the mic (the web's vtStartMic callback).
    @State private var pendingStart: PendingStart = .none

    private static let tickTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🎙️ مدرّب الصوت")
                    .font(.title3).bold()
                Text("درّب صوتك زي ما بتتدرّب على آلة: شوف نغمتك على شبكة أرباع التون الحقيقية، ثبّت عليها، واتدرّب على المقامات نغمة نغمة بتقييم. التحليل كله على جهازك وصوتك مش بيتبعت لأي مكان.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            readoutSection
            holdSection
            droneSection
            exerciseSection
            rangeSection
        }
        .onReceive(engine.$rawMidi) { value in
            pushPitch(value)
        }
        .onReceive(Self.tickTimer) { now in
            tick(now)
        }
        .onChange(of: engine.isListening) { listening in
            if !listening { handleMicStopped() }
        }
        .onDisappear {
            if droneOn {
                engine.stopDrone()
                droneOn = false
            }
            if exActive {
                exActive = false
                exPhase = .idle
            }
            pendingStart = .none
        }
    }

    // MARK: Readout + hold meter UI

    private var readoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("صوتك لايف — على شبكة أرباع التون")
                .font(.headline)
            HStack(spacing: 10) {
                readoutBox(title: "النغمة اللي بتغنّيها",
                           value: detectedMidi.map { noteLabel(forQuarterMidi: ($0 * 2).rounded() / 2) } ?? "—")
                readoutBox(title: "التردد",
                           value: detectedMidi.map { "\(Int(frequency(ofMidi: $0).rounded())) Hz" } ?? "—")
                readoutBox(title: "بعدك عن أقرب نغمة",
                           value: readoutCents.text,
                           color: readoutCents.good ? .green : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readoutCents: (text: String, good: Bool) {
        guard let detected = detectedMidi else { return ("—", false) }
        let quarter = (detected * 2).rounded() / 2
        let cents = Int(((detected - quarter) * 100).rounded())
        return ("\(cents > 0 ? "+" : "")\(cents)¢", abs(cents) <= 25)
    }

    private func readoutBox(title: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.title3).bold()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private var holdSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⏱ ثبات النغمة — اختبار النَّفَس والدقة")
                .font(.headline)
            Text("ثبّت على أي نغمة من غير ما تهتز بره ±١٥ سنت: بتثبت دلوقتي من \(String(format: "%.1f", holdSeconds)) ثانية · أحسن ثبات لك: \(String(format: "%.1f", holdBest)) ثانية")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
    }

    // MARK: Drone UI

    private var droneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎵 نغمة مرجعية ثابتة (درون)")
                .font(.headline)
            Text("نغمة بتفضل شغالة وانت بتغنّي عليها — أحسن طريقة تظبط ودنك على الركوز. اختار النغمة وشغّلها، وممكن تضيف الخامسة والأوكتاف فوقها.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Picker("النغمة المرجعية", selection: $droneMidi) {
                ForEach(quarterGrid(from: 43, to: 72), id: \.self) { midi in
                    Text(noteLabel(forQuarterMidi: midi)).tag(midi)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: droneMidi) { _ in refreshDrone() }
            Toggle("+ الخامسة", isOn: $droneFifth)
                .onChange(of: droneFifth) { _ in refreshDrone() }
            Toggle("+ الأوكتاف", isOn: $droneOctave)
                .onChange(of: droneOctave) { _ in refreshDrone() }
            Button(droneOn ? "⏹ وقّف الدرون" : "▶ شغّل الدرون") {
                toggleDrone()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
    }

    // MARK: Exercise UI

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎼 تمرين مقام موجّه — قول ورايا")
                .font(.headline)
            Text("اختار المقام ونغمة بداية تناسب طبقة صوتك: هتسمع كل نغمة من السلّم (صعودًا ونزولًا)، وبعد كل نغمة هسكت واسمعك وانت بتغنّيها، واحسب درجتك على قد إيه فضلت مظبوط جوه حد الدقة. أي أوكتاف منك مقبول — بنقارن نغمتك بنفس النغمة على طبقتك.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Picker("المقام", selection: $exMaqam) {
                ForEach(Maqam.all) { maqam in
                    Text(maqam.nameArabic).tag(maqam)
                }
            }
            .pickerStyle(.menu)
            Picker("نغمة البداية (على طبقتك)", selection: $exTonicMidi) {
                ForEach(quarterGrid(from: 43, to: 67), id: \.self) { midi in
                    Text(noteLabel(forQuarterMidi: midi)).tag(midi)
                }
            }
            .pickerStyle(.menu)
            Picker("الجولات", selection: $exRounds) {
                Text("جولة واحدة").tag(1)
                Text("جولتين").tag(2)
                Text("٣ جولات").tag(3)
            }
            .pickerStyle(.segmented)
            Picker("السرعة", selection: $exSpeedMs) {
                Text("بطيئة").tag(3400)
                Text("متوسطة").tag(2600)
                Text("سريعة").tag(1900)
            }
            .pickerStyle(.segmented)
            Picker("الدقة المطلوبة", selection: $exAccuracy) {
                Text("±٤٠ سنت (متساهلة)").tag(40)
                Text("±٢٥ سنت (مظبوطة)").tag(25)
                Text("±١٥ سنت (صارمة)").tag(15)
            }
            .pickerStyle(.segmented)
            Button(exActive || pendingStart == .exercise ? "⏹ وقّف التمرين" : "🎤 ابدأ التمرين") {
                toggleExercise()
            }
            .buttonStyle(.borderedProminent)

            if exActive || exPhase == .finished || !exLastMessage.isEmpty {
                VStack(spacing: 6) {
                    if !exPhaseText.isEmpty {
                        Text(exPhaseText)
                            .font(.headline)
                    }
                    if exActive && exIndex < exSequence.count {
                        Text(exSequence[exIndex].label)
                            .font(.title2).bold()
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    if !exSequence.isEmpty {
                        chipsView
                    }
                    if !exLastMessage.isEmpty {
                        Text(exLastMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if let score = exFinalScore, !exActive {
                VStack(spacing: 4) {
                    Text("درجتك: \(score)٪")
                        .font(.headline)
                        .foregroundColor(.green)
                    Text(exTendency)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.12))
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
    }

    private var exPhaseText: String {
        switch exPhase {
        case .playing: return "🔊 اسمع النغمة…"
        case .listening: return "🎤 دورك — غنّيها"
        case .between: return "اللي بعدها…"
        case .finished: return "🏁 خلّصت التمرين"
        case .idle: return ""
        }
    }

    private var chipsView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
            ForEach(Array(exSequence.enumerated()), id: \.offset) { index, note in
                Text(note.label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(chipColor(for: index))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(index == exIndex && exActive ? Color.orange : Color.clear, lineWidth: 2)
                    )
            }
        }
    }

    private func chipColor(for index: Int) -> Color {
        if index < exResults.count {
            return exResults[index].score >= 60 ? Color.green.opacity(0.3) : Color.red.opacity(0.25)
        }
        return Color.gray.opacity(0.15)
    }

    // MARK: Range UI

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎤 مداك الصوتي")
                .font(.headline)
            Text("اعرف حدود صوتك: غنّي أوطى نغمة مريحة وثبّت عليها ثانية، وبعدين أعلى نغمة مريحة وثبّت عليها — من غير ما تزعق أو تتعب صوتك.")
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("ابدأ قياس المدى") {
                    toggleRange()
                }
                .buttonStyle(.borderedProminent)
                Button("من الأول") {
                    resetRange()
                }
                .buttonStyle(.bordered)
            }
            Text(rangeStatus)
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                readoutBox(title: "أوطى نغمة",
                           value: rangeLow.map { noteLabel(forQuarterMidi: $0) } ?? "—")
                readoutBox(title: "أعلى نغمة",
                           value: rangeHigh.map { noteLabel(forQuarterMidi: $0) } ?? "—")
            }
            if let result = rangeResultText {
                Text(result)
                    .font(.subheadline).bold()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
    }

    private var rangeResultText: String? {
        guard let low = rangeLow, let high = rangeHigh else { return nil }
        let span = high - low
        var text = "مداك الصوتي: من \(noteLabel(forQuarterMidi: low)) لـ \(noteLabel(forQuarterMidi: high)) — \(String(format: "%.1f", span)) نص تون"
        if span >= 12 { text += " (أكتر من أوكتاف كامل)" }
        return text
    }

    // MARK: Helpers

    private func frequency(ofMidi midi: Double) -> Double {
        440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }

    /// English name + octave for a pitch on the quarter-tone grid,
    /// using the app's own naming table (e.g. "E half-flat3").
    private func noteLabel(forQuarterMidi quarter: Double) -> String {
        let name = Maqam.absoluteNoteName(absoluteCents: Int((quarter * 100).rounded()))
        let octave = Int(floor(quarter / 12.0)) - 1
        return "\(name)\(octave)"
    }

    /// Quarter-tone grid values (step 0.5 MIDI) for the note pickers.
    private func quarterGrid(from low: Int, to high: Int) -> [Double] {
        stride(from: Double(low), through: Double(high), by: 0.5).map { $0 }
    }

    /// Fold a detected pitch into the target's octave (any octave of
    /// the target counts), exactly like the web's foldToTarget.
    private func foldToTarget(_ detected: Double, _ target: Double) -> Double {
        var folded = detected
        while folded - target > 6 { folded -= 12 }
        while target - folded > 6 { folded += 12 }
        return folded
    }

    // MARK: Pitch intake + tick

    /// One smoother push per capture buffer (the engine publishes
    /// `rawMidi` once per buffer while listening).
    private func pushPitch(_ midi: Double?) {
        guard engine.isListening else {
            smoother.reset()
            detectedMidi = nil
            return
        }
        guard let midi = midi else {
            _ = smoother.push(nil)
            detectedMidi = nil
            return
        }
        if let stable = smoother.push(midi) {
            detectedMidi = stable
        }
    }

    private func tick(_ now: Date) {
        // Deferred starts fire as soon as the mic is live.
        if pendingStart != .none {
            if engine.isListening {
                let pending = pendingStart
                pendingStart = .none
                switch pending {
                case .exercise: beginExercise(now)
                case .range: beginRange()
                case .none: break
                }
            } else if engine.permissionDenied {
                let pending = pendingStart
                pendingStart = .none
                switch pending {
                case .exercise:
                    exLastMessage = "⚠ إذن المايك مرفوض — التمرين محتاج المايك شغال"
                case .range:
                    rangeStatus = "⚠ إذن المايك مرفوض — قياس المدى محتاج المايك شغال"
                case .none:
                    break
                }
            }
        }
        updateHold(now)
        exerciseTick(now)
        rangeTick(now)
    }

    /// Mic stopped (coach button, or the session ended): cancel the
    /// exercise and any in-progress range capture, like the web's
    /// vtStopMic. The drone is playback-only and is left alone.
    private func handleMicStopped() {
        smoother.reset()
        detectedMidi = nil
        holdQuarter = nil
        holdSince = nil
        holdSeconds = 0
        pendingStart = .none
        if exActive {
            exActive = false
            exPhase = .idle
        }
        if rangeMode == .low || rangeMode == .high {
            rangeMode = .idle
            rangeCandidate = nil
            rangeCandidateSince = nil
            rangeStatus = "اتوقف المايك — شغّله وابدأ قياس المدى من الأول"
        }
    }

    // MARK: Hold meter

    private func updateHold(_ now: Date) {
        guard engine.isListening, let detected = detectedMidi else {
            holdQuarter = nil
            holdSince = nil
            holdSeconds = 0
            return
        }
        let quarter = (detected * 2).rounded() / 2
        if abs((detected - quarter) * 100) <= 15 {
            if holdQuarter != quarter {
                holdQuarter = quarter
                holdSince = now
            }
            let held = now.timeIntervalSince(holdSince ?? now)
            holdSeconds = held
            if held > holdBest { holdBest = held }
        } else {
            holdQuarter = nil
            holdSince = nil
            holdSeconds = 0
        }
    }

    // MARK: Drone control

    private func toggleDrone() {
        if droneOn {
            engine.stopDrone()
            droneOn = false
        } else {
            engine.startDrone(baseFrequency: frequency(ofMidi: droneMidi),
                              fifth: droneFifth, octave: droneOctave)
            droneOn = true
        }
    }

    private func refreshDrone() {
        if droneOn {
            engine.startDrone(baseFrequency: frequency(ofMidi: droneMidi),
                              fifth: droneFifth, octave: droneOctave)
        }
    }

    // MARK: Guided exercise

    private func toggleExercise() {
        if exActive || pendingStart == .exercise {
            exActive = false
            exPhase = .idle
            pendingStart = .none
            return
        }
        exFinalScore = nil
        exTendency = ""
        if engine.isListening {
            beginExercise(Date())
        } else {
            engine.startListening()
            pendingStart = .exercise
        }
    }

    private func beginExercise(_ now: Date) {
        let count = exMaqam.scaleCents.count
        let up = Array(0..<count)
        let down = Array((0..<(count - 1)).reversed())
        var sequence: [ExerciseNote] = []
        for _ in 0..<exRounds {
            for index in up + down {
                let targetMidi = exTonicMidi + Double(exMaqam.scaleCents[index]) / 100.0
                sequence.append(ExerciseNote(
                    label: noteLabel(forQuarterMidi: targetMidi),
                    targetMidi: targetMidi,
                    frequency: frequency(ofMidi: targetMidi)))
            }
        }
        exSequence = sequence
        exIndex = 0
        exResults = []
        exAllCents = []
        exLastMessage = "النغمة 1 من \(sequence.count)"
        exActive = true
        playCurrentNote(now)
    }

    private func playCurrentNote(_ now: Date) {
        guard exActive else { return }
        if exIndex >= exSequence.count {
            finishExercise()
            return
        }
        exPhase = .playing
        let note = exSequence[exIndex]
        engine.playTone(frequency: note.frequency, duration: 1.1)
        // Detection stays muted while the guide sounds, plus 350 ms.
        exMutedUntil = now.addingTimeInterval(1.45)
        exPhaseEnd = now.addingTimeInterval(1.5)
    }

    private func exerciseTick(_ now: Date) {
        guard exActive else { return }
        switch exPhase {
        case .playing:
            if now >= exPhaseEnd {
                exPhase = .listening
                exFrames = 0
                exInFrames = 0
                exCentsSum = 0
                exListenEnd = now.addingTimeInterval(Double(exSpeedMs) / 1000.0)
            }
        case .listening:
            if now >= exListenEnd {
                scoreCurrentNote(now)
            } else if now >= exMutedUntil, engine.isListening,
                      let detected = detectedMidi, exIndex < exSequence.count {
                let target = exSequence[exIndex].targetMidi
                let cents = (foldToTarget(detected, target) - target) * 100
                exFrames += 1
                exCentsSum += cents
                exAllCents.append(cents)
                if abs(cents) <= Double(exAccuracy) { exInFrames += 1 }
            }
        case .between:
            if now >= exPhaseEnd {
                playCurrentNote(now)
            }
        case .idle, .finished:
            break
        }
    }

    private func scoreCurrentNote(_ now: Date) {
        guard exIndex < exSequence.count else { return }
        let note = exSequence[exIndex]
        let score = exFrames > 0
            ? Int((Double(exInFrames) / Double(exFrames) * 100).rounded())
            : 0
        let avg = exFrames > 0
            ? Int((exCentsSum / Double(exFrames)).rounded())
            : 0
        exResults.append(ExerciseResult(label: note.label, score: score,
                                        avgCents: avg, heard: exFrames > 0))
        if exFrames > 0 {
            if abs(avg) >= 8 {
                let tendency = avg > 0 ? "ميلك فيها حاد +\(avg) سنت" : "ميلك فيها خافت \(avg) سنت"
                exLastMessage = "نغمة \(note.label): درجتك \(score)٪ — \(tendency)"
            } else {
                exLastMessage = "نغمة \(note.label): درجتك \(score)٪ — مظبوطة في النص"
            }
        } else {
            exLastMessage = "نغمة \(note.label): مسمعتش صوتك فيها — الدرجة ٠٪"
        }
        exIndex += 1
        exPhase = .between
        exPhaseEnd = now.addingTimeInterval(0.65)
    }

    private func finishExercise() {
        exActive = false
        exPhase = .finished
        let total = exResults.reduce(0) { $0 + $1.score }
        exFinalScore = exResults.isEmpty
            ? 0
            : Int((Double(total) / Double(exResults.count)).rounded())
        if exAllCents.isEmpty {
            exTendency = "مسمعتش صوتك في التمرين ده — قرّب الموبايل منك وغنّي بصوت أوضح المرة الجاية."
        } else {
            let avgC = Int((exAllCents.reduce(0.0, +) / Double(exAllCents.count)).rounded())
            if avgC > 8 {
                exTendency = "ميلك العام: حاد — بتغنّي أعلى من الصح بشوية (متوسط +\(avgC) سنت). جرّب تريّح صوتك سنة لتحت."
            } else if avgC < -8 {
                exTendency = "ميلك العام: خافت — بتغنّي أوطى من الصح بشوية (متوسط \(avgC) سنت). جرّب ترفع صوتك سنة لفوق."
            } else {
                exTendency = "ميلك العام: مظبوط في النص — متوسط انحرافك \(avgC > 0 ? "+" : "")\(avgC) سنت بس."
            }
        }
    }

    // MARK: Range finder

    private func toggleRange() {
        if engine.isListening {
            beginRange()
        } else {
            engine.startListening()
            pendingStart = .range
        }
    }

    private func beginRange() {
        rangeMode = .low
        rangeLow = nil
        rangeHigh = nil
        rangeCandidate = nil
        rangeCandidateSince = nil
        rangeStatus = "🎤 غنّي أوطى نغمة مريحة عندك وثبّت عليها ثانية…"
    }

    private func resetRange() {
        rangeMode = .idle
        rangeLow = nil
        rangeHigh = nil
        rangeCandidate = nil
        rangeCandidateSince = nil
        rangeStatus = "المايك لازم يكون شغال — شغّله من زرار «ابدأ الاستماع» فوق أو من زرار البدء هنا على طول."
    }

    private func rangeTick(_ now: Date) {
        guard rangeMode == .low || rangeMode == .high else { return }
        guard engine.isListening, let detected = detectedMidi else {
            rangeCandidate = nil
            rangeCandidateSince = nil
            return
        }
        let quarter = (detected * 2).rounded() / 2
        if abs((detected - quarter) * 100) > 30 {
            rangeCandidate = nil
            rangeCandidateSince = nil
            return
        }
        if rangeMode == .high, let low = rangeLow, quarter <= low {
            rangeCandidate = nil
            rangeCandidateSince = nil
            rangeStatus = "دي أوطى من أوطى نغمة سجلتها أو قدها بالظبط — اطلع أعلى منها"
            return
        }
        if rangeCandidate != quarter {
            rangeCandidate = quarter
            rangeCandidateSince = now
            return
        }
        guard let since = rangeCandidateSince,
              now.timeIntervalSince(since) >= 0.8 else { return }
        if rangeMode == .low {
            rangeLow = quarter
            rangeMode = .high
            rangeCandidate = nil
            rangeCandidateSince = nil
            rangeStatus = "تمام، اتسجلت أوطى نغمة: \(noteLabel(forQuarterMidi: quarter)) — دلوقتي غنّي أعلى نغمة مريحة وثبّت عليها"
        } else {
            rangeHigh = quarter
            rangeMode = .done
            rangeCandidate = nil
            rangeCandidateSince = nil
            rangeStatus = "اتقاس مداك — دوس «من الأول» لو عايز تعيد القياس"
        }
    }
}
