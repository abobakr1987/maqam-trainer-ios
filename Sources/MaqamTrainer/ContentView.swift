import SwiftUI

/// The app's top-level tabs. Course-path items jump between tabs through
/// the shared selection binding.
enum AppTab: Hashable {
    case coach, teacher, transitions, course, maqams, piano
}

struct ContentView: View {
    @StateObject private var engine = AudioEngine()
    @StateObject private var courseProgress = CourseProgress()
    @State private var selectedTab: AppTab = .coach

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                CoachView()
            }
            .tabItem { Label("المدرب اللايف", systemImage: "mic.fill") }
            .tag(AppTab.coach)

            NavigationView {
                TeacherView()
            }
            .tabItem { Label("المدرّس", systemImage: "graduationcap.fill") }
            .tag(AppTab.teacher)

            NavigationView {
                TransitionsView()
            }
            .tabItem { Label("الانتقالات", systemImage: "arrow.left.arrow.right") }
            .tag(AppTab.transitions)

            NavigationView {
                CoursePathView(selectedTab: $selectedTab)
            }
            .tabItem { Label("مسار الإتقان", systemImage: "map.fill") }
            .tag(AppTab.course)

            NavigationView {
                MaqamListView()
            }
            .tabItem { Label("المقامات", systemImage: "music.note.list") }
            .tag(AppTab.maqams)

            NavigationView {
                PianoView()
            }
            .tabItem { Label("البيانو", systemImage: "pianokeys") }
            .tag(AppTab.piano)
        }
        .environmentObject(engine)
        .environmentObject(courseProgress)
    }
}

/// Maqam reference: tonic, English degree names, and the character note
/// for each of the nine maqams — plus the teacher's recorded voice for
/// every maqam that has one. Per the app's rule, a maqam's scale in the
/// learning screens is SUNG in the recorded human voice; piano tones
/// live only in the piano tab. A maqam whose recording has not arrived
/// yet honestly shows «بيتحضّر» instead of any substitute sound.
struct MaqamListView: View {
    @StateObject private var player = TeacherPlayer()
    @State private var playingMaqamID: String?
    @State private var playingKind: TeacherAudioKind?
    private let library = TeacherAudioLibrary()

    var body: some View {
        List(Maqam.all) { maqam in
            Section(header: Text("\(maqam.nameArabic) — الركوز \(maqam.tonicName)")) {
                Text(maqam.degreeNames.joined(separator: " · "))
                    .font(.callout)
                Text(maqam.comment)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                audioRow(for: maqam, kind: .scale,
                         title: "🎤 اسمع السلّم بصوت المدرّس",
                         missingNote: "السلّم الصوتي بيتحضّر")
                audioRow(for: maqam, kind: .phrase,
                         title: "🎵 اسمع جملة بالمقام بصوت المدرّس",
                         missingNote: nil)
            }
        }
        .navigationTitle("المقامات")
        .onDisappear { player.stop() }
        .onChange(of: player.isPlaying) { playing in
            if !playing {
                playingMaqamID = nil
                playingKind = nil
            }
        }
    }

    private func isPlaying(_ maqam: Maqam, _ kind: TeacherAudioKind) -> Bool {
        player.isPlaying && playingMaqamID == maqam.id && playingKind == kind
    }

    @ViewBuilder
    private func audioRow(for maqam: Maqam, kind: TeacherAudioKind,
                          title: String, missingNote: String?) -> some View {
        if let url = library.url(forMaqamID: maqam.id, kind: kind) {
            Button {
                if isPlaying(maqam, kind) {
                    player.stop()
                } else {
                    playingMaqamID = maqam.id
                    playingKind = kind
                    player.play(url: url, kind: kind)
                }
            } label: {
                Label(isPlaying(maqam, kind) ? "⏹ وقّف" : title,
                      systemImage: isPlaying(maqam, kind) ? "stop.fill" : "play.fill")
            }
        } else if let missingNote {
            Text(missingNote)
                .font(.footnote)
                .foregroundColor(.orange)
        }
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
