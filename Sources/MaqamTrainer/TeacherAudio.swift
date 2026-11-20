import Foundation
import AVFoundation

/// One maqam's teacher audio files, as named in TeacherAudio/manifest.json.
struct TeacherAudioEntry: Codable {
    /// Scale sung up/down on "آه" by the AI teacher.
    let scale: String
    /// Short phrase sung by the AI teacher, ending on the tonic.
    let phrase: String
}

enum TeacherAudioKind {
    case scale
    case phrase
}

/// Loads the drop-in teacher audio bundle.
///
/// Audio files live in Sources/MaqamTrainer/TeacherAudio/ and are mapped
/// per maqam id in its manifest.json. The files themselves are produced
/// and pitch-verified separately and simply dropped into that folder —
/// no code change is needed when they arrive. A missing file is a normal
/// state: the UI then shows «الدرس الصوتي بيتحضّر» and still shows the
/// teacher's written lesson. There is deliberately NO fallback to any
/// external video or link anywhere in this app — everything is bundled.
final class TeacherAudioLibrary {
    private let manifest: [String: TeacherAudioEntry]

    init() {
        var loaded: [String: TeacherAudioEntry] = [:]
        if let url = Self.bundleURL(forResource: "manifest", withExtension: "json",
                                     subdirectory: "TeacherAudio"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: TeacherAudioEntry].self, from: data) {
            loaded = decoded
        }
        manifest = loaded
    }

    /// URL of the bundled audio file for a maqam, or nil if it has not
    /// been dropped in yet.
    func url(forMaqamID id: String, kind: TeacherAudioKind) -> URL? {
        guard let entry = manifest[id] else { return nil }
        let filename = (kind == .scale) ? entry.scale : entry.phrase
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return Self.bundleURL(forResource: name, withExtension: ext,
                              subdirectory: "TeacherAudio")
    }

    func hasAudio(forMaqamID id: String, kind: TeacherAudioKind) -> Bool {
        url(forMaqamID: id, kind: kind) != nil
    }

    private static func bundleURL(forResource name: String, withExtension ext: String,
                                  subdirectory: String) -> URL? {
        // SPM resource bundle first, app bundle as a fallback for when the
        // sources are later wrapped in a regular Xcode app project.
        for bundle in [Bundle.module, Bundle.main] {
            if let url = bundle.url(forResource: name, withExtension: ext,
                                    subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }
}

/// The teacher's spoken lesson line for each maqam, shown as text under
/// the avatar. This is the text the bundled audio speaks/sings along with.
enum TeacherIntros {
    static func text(forMaqamID id: String) -> String {
        switch id {
        case "rast":
            return "أهلاً بيك، أنا مدرّسك. الراست ملك المقامات وركوزه C. اسمعني بغنّي السلّم على «آه» وبعدين قوله ورايا بنفس النفس."
        case "bayati":
            return "البياتي مقام الشجن، وركوزه D وأول درجة بعد الركوز ربع تون. اسمع الجنس الأول كويس وقوله ورايا."
        case "hijaz":
            return "الحجاز علامته البعد الكبير بين أول درجتين. اسمع القفزة دي بصوتي وقولها ورايا من غير ما تستعجل."
        case "nahawand":
            return "النهاوند قريب من المينور بس قفلته طعمها شرقي. اسمع السلّم والجملة وقول ورايا."
        case "kurd":
            return "الكرد هادي وحزين ومفيهوش أرباع تون، فدقّتك هنا في النقاء بس. اسمع وقول ورايا."
        case "saba":
            return "الصبا أحزن المقامات ودرجته الرابعة نازلة. حسّ بالحزن ده وانت بتقول السلّم ورايا."
        case "sikah":
            return "السيكاه ركوزه نفسه ربع تون: E half-flat. ثبّت ودنك على الدرجة دي الأول، وبعدين قول ورايا."
        case "ajam":
            return "العجم على Bb وطابعه فخم وواضح زي الماجور. اسمع السلّم وقوله ورايا بثقة."
        case "hijazkar":
            return "الحجاز كار حجاز على C بسابعة كبيرة حادة. اسمع القفلة على الركوز وقولها ورايا."
        default:
            return "اسمع الدرس وقوله ورايا."
        }
    }
}

/// Plays the bundled teacher audio files with AVAudioPlayer.
final class TeacherPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    @Published var currentKind: TeacherAudioKind?

    private var player: AVAudioPlayer?

    func play(url: URL, kind: TeacherAudioKind) {
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
            isPlaying = true
            currentKind = kind
        } catch {
            isPlaying = false
            currentKind = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentKind = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.currentKind = nil
            self?.player = nil
        }
    }
}
