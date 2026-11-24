import SwiftUI

/// One phase of a breathing cycle.
struct BreathPhase {
    enum Kind {
        case inhale, hold, exhale

        var label: String {
            switch self {
            case .inhale: return "اسحب نفَس"
            case .hold: return "امسك النفس"
            case .exhale: return "طلّع النفس"
            }
        }
    }

    let kind: Kind
    let seconds: Double
}

/// A guided breathing pattern for singers. Phases may depend on the
/// round number (the graduated pattern lengthens its exhale each round).
struct BreathingPattern: Identifiable {
    let id: String
    let name: String
    let detail: String
    /// Exhale is done as a long steady hiss ("سسس") for air support.
    let hissExhale: Bool
    let phasesForRound: (Int) -> [BreathPhase]

    static let all: [BreathingPattern] = [
        BreathingPattern(
            id: "calm",
            name: "تنفس هادئ ٤-٤-٨",
            detail: "اسحب النفس ٤ ثوانٍ من الأنف، امسكه ٤، وطلّعه ٨ بهدوء. ده أساس التحكم في النفس قبل أي غنا.",
            hissExhale: false,
            phasesForRound: { _ in
                [BreathPhase(kind: .inhale, seconds: 4),
                 BreathPhase(kind: .hold, seconds: 4),
                 BreathPhase(kind: .exhale, seconds: 8)]
            }),
        BreathingPattern(
            id: "hiss",
            name: "ثبات الهواء — الهسيس الطويل",
            detail: "اسحب النفس ٤ ثوانٍ، امسكه ثانيتين، وبعدين طلّعه على هسيس ثابت «سسس» لأطول وقت تقدر من غير ما الصوت يهتز أو يضعف. ده تمرين دعم الهواء نفسه اللي بيخلي النغمة الطويلة ثابتة.",
            hissExhale: true,
            phasesForRound: { _ in
                [BreathPhase(kind: .inhale, seconds: 4),
                 BreathPhase(kind: .hold, seconds: 2),
                 BreathPhase(kind: .exhale, seconds: 14)]
            }),
        BreathingPattern(
            id: "graduated",
            name: "نفَس الغنا المتدرج",
            detail: "اسحب ٤ وامسك ٤، والنفَس الطالع بيطوّل كل جولة: ٨ ثم ١٠ ثم ١٢ ثانية وهكذا — زي ما الجمل الغنائية بتطوّل وانت بتتقدم في المقام.",
            hissExhale: false,
            phasesForRound: { round in
                let exhale = min(8.0 + 2.0 * Double(round - 1), 20.0)
                return [BreathPhase(kind: .inhale, seconds: 4),
                        BreathPhase(kind: .hold, seconds: 4),
                        BreathPhase(kind: .exhale, seconds: exhale)]
            })
    ]
}

/// Drives one breathing session: walks the pattern's phases round by
/// round on a 50 ms timer and publishes everything the view animates.
///
/// The module is deliberately VISUAL ONLY: it never touches the audio
/// session, so it can never fight the live coach's microphone session or
/// the teacher/transitions players (the app's one-audio-session rule).
final class BreathingSession: ObservableObject {
    @Published var isRunning = false
    @Published var isFinished = false
    @Published var round = 1
    @Published var phaseKind: BreathPhase.Kind = .inhale
    @Published var phaseSecondsLeft: Double = 0

    private(set) var phaseDuration: Double = 1
    private(set) var totalRounds = 5
    private var pattern: BreathingPattern?
    private var phases: [BreathPhase] = []
    private var phaseIndex = 0
    private var timer: Timer?

    /// 0...1 progress inside the current phase.
    var phaseProgress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - phaseSecondsLeft / phaseDuration))
    }

    func start(pattern: BreathingPattern, rounds: Int) {
        stop()
        self.pattern = pattern
        totalRounds = rounds
        round = 1
        isFinished = false
        isRunning = true
        beginRound()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func beginRound() {
        guard let pattern = pattern else { return }
        phases = pattern.phasesForRound(round)
        phaseIndex = 0
        beginPhase()
    }

    private func beginPhase() {
        guard phases.indices.contains(phaseIndex) else { return }
        let phase = phases[phaseIndex]
        phaseKind = phase.kind
        phaseDuration = phase.seconds
        phaseSecondsLeft = phase.seconds
    }

    private func tick() {
        phaseSecondsLeft -= 0.05
        if phaseSecondsLeft <= 0 {
            advance()
        }
    }

    private func advance() {
        phaseIndex += 1
        if phaseIndex < phases.count {
            beginPhase()
            return
        }
        if round >= totalRounds {
            stop()
            isFinished = true
        } else {
            round += 1
            beginRound()
        }
    }

    deinit {
        timer?.invalidate()
    }
}

/// «تمرين النفس»: guided breathing cycles for singers, with an animated
/// circle that grows on the inhale, holds, and shrinks on the exhale.
struct BreathingView: View {
    @StateObject private var session = BreathingSession()
    @State private var selectedPattern: BreathingPattern = BreathingPattern.all[0]
    @State private var rounds: Int = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if session.isRunning || session.isFinished {
                    sessionView
                } else {
                    setupView
                }
            }
            .padding()
        }
        .navigationTitle("تمرين النفس")
        .onDisappear { session.stop() }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 20) {
            Text("النفس هو وقود الغنا. اختار نمط وابدأ، وخلي كتفك ورقبتك مرتاحين وانت بتتنفس من بطنك مش من صدرك.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            ForEach(BreathingPattern.all) { pattern in
                Button {
                    selectedPattern = pattern
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pattern.name).font(.headline)
                            Spacer()
                            if selectedPattern.id == pattern.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        Text(pattern.detail)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(selectedPattern.id == pattern.id ? 0.15 : 0.05))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            Stepper("عدد الجولات: \(rounds)", value: $rounds, in: 1...12)
                .font(.callout)

            Button("▶️ ابدأ التمرين") {
                session.start(pattern: selectedPattern, rounds: rounds)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Running session

    private var sessionView: some View {
        VStack(spacing: 24) {
            if session.isFinished {
                Text("🎉 خلصت \(session.totalRounds) جولات")
                    .font(.title3).bold()
                Text("نفسك بقى أهدى وأطول. ارجع وكرر التمرين أو ادخل على تدريب المقامات وانت جاهز.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("↩️ ارجع للأنماط") {
                    session.isFinished = false
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("الجولة \(session.round) من \(session.totalRounds)")
                    .font(.headline)
                    .foregroundColor(.secondary)

                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 220, height: 220)
                        .scaleEffect(circleScale)
                    Circle()
                        .stroke(Color.orange.opacity(0.35), lineWidth: 6)
                        .frame(width: 230, height: 230)
                    VStack(spacing: 6) {
                        Text(session.phaseKind.label)
                            .font(.title3).bold()
                        Text("\(Int(ceil(session.phaseSecondsLeft)))")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                    }
                }
                .frame(height: 260)
                .animation(.linear(duration: 0.05), value: session.phaseSecondsLeft)

                if selectedPattern.hissExhale && session.phaseKind == .exhale {
                    Text("طلّع الهواء على «سسس» ثابتة — من غير دفعات")
                        .font(.callout)
                        .foregroundColor(.orange)
                }

                Button("⏹ وقّف التمرين") { session.stop() }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// Circle grows while inhaling, stays full on the hold, and shrinks
    /// while exhaling.
    private var circleScale: CGFloat {
        let progress = CGFloat(session.phaseProgress)
        switch session.phaseKind {
        case .inhale: return 0.55 + 0.45 * progress
        case .hold: return 1.0
        case .exhale: return 1.0 - 0.45 * progress
        }
    }
}
