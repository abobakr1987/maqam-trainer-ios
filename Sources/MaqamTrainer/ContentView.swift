import SwiftUI

struct ContentView: View {
    @StateObject private var engine = AudioEngine()

    var body: some View {
        TabView {
            NavigationView {
                CoachView()
            }
            .tabItem { Label("المدرب اللايف", systemImage: "mic.fill") }

            NavigationView {
                TeacherView()
            }
            .tabItem { Label("المدرّس", systemImage: "graduationcap.fill") }

            NavigationView {
                MaqamListView()
            }
            .tabItem { Label("المقامات", systemImage: "music.note.list") }

            NavigationView {
                PianoView()
            }
            .tabItem { Label("البيانو", systemImage: "pianokeys") }
        }
        .environmentObject(engine)
    }
}

/// Simple maqam reference: tonic, English degree names, and the character
/// note for each of the nine maqams.
struct MaqamListView: View {
    var body: some View {
        List(Maqam.all) { maqam in
            Section(header: Text("\(maqam.nameArabic) — الركوز \(maqam.tonicName)")) {
                Text(maqam.degreeNames.joined(separator: " · "))
                    .font(.callout)
                Text(maqam.comment)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("المقامات")
    }
}

/// Minimal piano: the selected maqam's scale as tappable keys, one octave
/// plus the octave tonic, each key playing its exact quarter-tone pitch.
struct PianoView: View {
    @EnvironmentObject private var engine: AudioEngine
    @State private var selectedMaqam: Maqam = Maqam.all[0]

    var body: some View {
        VStack(spacing: 20) {
            Picker("المقام", selection: $selectedMaqam) {
                ForEach(Maqam.all) { maqam in
                    Text(maqam.nameArabic).tag(maqam)
                }
            }
            .pickerStyle(.menu)

            Text("دوس على أي درجة وهتسمعها بتونها بالظبط — أرباع التون محسوبة بالسنت.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                ForEach(Array(selectedMaqam.scaleCents.enumerated()), id: \.offset) { index, cents in
                    Button {
                        engine.playTone(frequency: selectedMaqam.frequency(forDegree: index),
                                        duration: 0.7)
                    } label: {
                        VStack {
                            Spacer()
                            Text(selectedMaqam.noteName(forDegree: index))
                                .font(.caption2)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(cents % 100 == 50 ? Color.yellow.opacity(0.55) : Color.white)
                        .border(Color.black.opacity(0.6), width: 1)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("🔊 اسمع السلّم كامل") {
                engine.playScale(of: selectedMaqam)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .navigationTitle("البيانو")
    }
}
