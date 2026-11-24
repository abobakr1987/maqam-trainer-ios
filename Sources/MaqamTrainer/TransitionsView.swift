import SwiftUI
import AVFoundation

/// One transition / combining exercise, as defined in
/// TeacherAudio/transitions/transitions.json (mirrors the exercises.json
/// produced with the recordings). The exercises were built ONLY by
/// cutting and joining the user's own recordings — no pitch processing —
/// so what plays here is the singer's real voice throughout.
struct TransitionExercise: Codable, Identifiable {
    let id: String
    let title_ar: String
    /// One of: نقلات محورية / نقلات عبارات / تدريبات الدمج وأصعب المقاطع
    let group: String
    let steps_ar: [String]
    /// Bundled audio file name inside TeacherAudio/transitions/.
    let file: String

    var title: String { title_ar }
    var steps: [String] { steps_ar }
}

/// Loads the bundled transition exercises and resolves their audio URLs.
final class TransitionLibrary {
    /// Group display order in the UI.
    static let groupOrder = ["نقلات محورية", "نقلات عبارات", "تدريبات الدمج وأصعب المقاطع"]

    let exercises: [TransitionExercise]

    init() {
        var loaded: [TransitionExercise] = []
        if let url = Self.bundleURL(forResource: "transitions", withExtension: "json",
                                     subdirectory: "TeacherAudio/transitions"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TransitionExercise].self, from: data) {
            loaded = decoded
        }
        exercises = loaded
    }

    /// Exercises of one group, in file order.
    func exercises(inGroup group: String) -> [TransitionExercise] {
        exercises.filter { $0.group == group }
    }

    /// URL of an exercise's bundled audio file, or nil if missing.
    func url(for exercise: TransitionExercise) -> URL? {
        let name = (exercise.file as NSString).deletingPathExtension
        let ext = (exercise.file as NSString).pathExtension
        return Self.bundleURL(forResource: name, withExtension: ext,
                              subdirectory: "TeacherAudio/transitions")
    }

    private static func bundleURL(forResource name: String, withExtension ext: String,
                                  subdirectory: String) -> URL? {
        // Same lookup pattern as TeacherAudioLibrary: SPM resource bundle
        // first, app bundle as fallback (Bundle.module == Bundle.main in
        // the Xcode app build, via BundleModuleShim).
        for bundle in [Bundle.module, Bundle.main] {
            if let url = bundle.url(forResource: name, withExtension: ext,
                                    subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }
}

/// Plays the bundled transition exercise files with AVAudioPlayer.
/// A single instance serves the whole list, so starting one exercise
/// always stops whichever was playing before.
final class TransitionPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingID: String?

    private var player: AVAudioPlayer?

    func toggle(exercise: TransitionExercise, url: URL) {
        if playingID == exercise.id {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                            mode: .default,
                                                            options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            playingID = exercise.id
        } catch {
            playingID = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.playingID = nil
            self?.player = nil
        }
    }
}

/// «الانتقالات والدمج»: transition and combining exercises built from the
/// user's own recordings, grouped as pivot transitions, phrase
/// transitions, and combining / hardest-passage drills.
struct TransitionsView: View {
    @StateObject private var player = TransitionPlayer()
    private let library = TransitionLibrary()

    var body: some View {
        List {
            Section {
                Text("التمارين دي متجمعة من تسجيلات حقيقية بصوت بشري — اسمع خطوة خطوة وقول وراها. النقلة المحورية بتحصل عند نغمة مشتركة بين المقامين، فودنك تتعلم تمسك النغمة دي وتبني عليها.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(TransitionLibrary.groupOrder, id: \.self) { group in
                let items = library.exercises(inGroup: group)
                if !items.isEmpty {
                    Section(header: Text(group)) {
                        ForEach(items) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }

            if library.exercises.isEmpty {
                Section {
                    Text("تمارين الانتقالات لسه بتتحضّر")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle("الانتقالات والدمج")
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: TransitionExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.title)
                        .font(.headline)
                    ForEach(Array(exercise.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let url = library.url(for: exercise) {
                    Button(player.playingID == exercise.id ? "⏹" : "▶️") {
                        player.toggle(exercise: exercise, url: url)
                    }
                    .font(.title3)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(player.playingID == exercise.id ? "وقّف" : "شغّل")
                } else {
                    Text("بيتحضّر")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
