import SwiftUI

/// The app's top-level tabs: five, so everything fits the tab bar
/// with no "More" overflow. Everything about one maqam lives on
/// that maqam's own page (reached from «المقامات»); the other tabs
/// are the shared gym (the live coach), transitions, the course
/// path, and the free piano.
enum AppTab: Hashable {
    case maqams, coach, transitions, course, piano
}

/// Cross-tab requests: a maqam page (or a course step) can ask the
/// coach to pre-select a maqam, or ask the maqam list to open one
/// maqam's page directly.
final class AppState: ObservableObject {
    @Published var coachMaqamID: String?
    @Published var openMaqamID: String?
}

struct ContentView: View {
    @StateObject private var engine = AudioEngine()
    @StateObject private var courseProgress = CourseProgress()
    @StateObject private var appState = AppState()
    @State private var selectedTab: AppTab = .maqams

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                MaqamListView(selectedTab: $selectedTab)
            }
            .tabItem { Label("المقامات", systemImage: "music.note.list") }
            .tag(AppTab.maqams)

            NavigationView {
                CoachView()
            }
            .tabItem { Label("المدرب اللايف", systemImage: "mic.fill") }
            .tag(AppTab.coach)

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
                PianoView()
            }
            .tabItem { Label("البيانو", systemImage: "pianokeys") }
            .tag(AppTab.piano)
        }
        .environmentObject(engine)
        .environmentObject(courseProgress)
        .environmentObject(appState)
    }
}

/// The nine maqams as one simple list. Tapping a maqam opens its
/// page — the single home for that maqam: the teacher's recorded
/// voice (scale + phrase), the written lesson, a jump into the
/// live coach pre-set to it, and its piano keys. Nothing about a
/// maqam lives anywhere else.
struct MaqamListView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var appState: AppState
    @State private var navSelection: String?
    private let library = TeacherAudioLibrary()

    var body: some View {
        List {
            ForEach(Maqam.all) { maqam in
                NavigationLink(tag: maqam.id, selection: $navSelection) {
                    MaqamPage(maqam: maqam, selectedTab: $selectedTab)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(maqam.nameArabic)
                            .font(.headline)
                        Text("الركوز \(maqam.tonicName) · \(maqam.degreeNames.joined(separator: " · "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                        if library.url(forMaqamID: maqam.id, kind: .scale) == nil {
                            Text("السلّم الصوتي بيتحضّر")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("المقامات")
        .onAppear { applyOpenRequest() }
        .onChange(of: appState.openMaqamID) { _ in applyOpenRequest() }
    }

    private func applyOpenRequest() {
        guard let id = appState.openMaqamID else { return }
        appState.openMaqamID = nil
        navSelection = id
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
