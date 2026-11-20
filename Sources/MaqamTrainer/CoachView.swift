import SwiftUI

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
            }
            .padding()
        }
        .navigationTitle("المدرب اللايف")
        .onAppear { engine.setMaqam(selectedMaqam) }
    }
}
